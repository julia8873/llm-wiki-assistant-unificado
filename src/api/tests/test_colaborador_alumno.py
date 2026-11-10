import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app, normalize_git_username
from app.db import get_session, Base, MapeoDB

engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

CFG = {"git": {"proveedor_activo": "github",
               "github": {"organizacion": "org", "api_base_url": "https://api.github.com"}}}
REPO = "https://github.com/org/Math101-alice.git"
HEADERS = {"Authorization": "Bearer test_token"}


def override_get_session():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(name="client")
def client_fixture():
    from app.core.config import settings
    settings.MAPEO_API_TOKEN = "test_token"
    app.dependency_overrides[get_session] = override_get_session
    Base.metadata.create_all(bind=engine)
    yield TestClient(app)
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.pop(get_session, None)


def _provider(collab_side_effect=None, exists=True):
    p = MagicMock()
    p.generar_repo_alumno = AsyncMock(return_value=REPO)
    p.añadir_colaborador = AsyncMock(side_effect=collab_side_effect)
    p.eliminar_colaborador = AsyncMock()
    p.usuario_existe = AsyncMock(return_value=exists)
    return p


def _payload(**kw):
    d = {"moodle_user_id": 1, "moodle_course_id": 1, "matrix_room_id": "!r:x",
         "moodle_username": "alice", "moodle_course_shortname": "Math101"}
    d.update(kw)
    return d


def _crear(client, provider, payload):
    with patch("app.main.get_git_provider", return_value=provider), \
         patch("app.services.git.load_config", return_value=CFG), \
         patch("app.main.sync_queue"):
        return client.post("/v1/mapeos", json=payload, headers=HEADERS)


def _llamar(client, provider, method, path, **kw):
    with patch("app.main.get_git_provider", return_value=provider):
        return client.request(method, path, headers=HEADERS, **kw)


# ---------- Fase 1: colaborador al crear el repo ----------

def test_alumno_con_git_username_se_anade_como_colaborador(client):
    prov = _provider()
    r = _crear(client, prov, _payload(git_username="alice-gh"))
    assert r.status_code == 201
    prov.añadir_colaborador.assert_awaited_once_with(REPO, "alice-gh", "push")
    assert r.json()["git_username"] == "alice-gh"


def test_arroba_inicial_se_normaliza(client):
    prov = _provider()
    _crear(client, prov, _payload(git_username="  @alice-gh "))
    prov.añadir_colaborador.assert_awaited_once_with(REPO, "alice-gh", "push")


def test_sin_git_username_no_se_usa_el_de_moodle(client):
    """El username de Moodle NO se usa como usuario de Git (podría ser una cuenta ajena)."""
    prov = _provider()
    r = _crear(client, prov, _payload())
    assert r.status_code == 201
    prov.añadir_colaborador.assert_not_awaited()
    assert r.json()["git_username"] is None


def test_git_username_invalido_se_ignora_sin_romper(client):
    prov = _provider()
    r = _crear(client, prov, _payload(git_username="../../etc"))
    assert r.status_code == 201
    prov.añadir_colaborador.assert_not_awaited()


def test_profesor_no_se_anade_como_colaborador(client):
    prov = _provider()
    r = _crear(client, prov, _payload(is_teacher=True, git_username="alice-gh"))
    assert r.status_code == 201
    prov.añadir_colaborador.assert_not_awaited()


def test_fallo_al_anadir_colaborador_no_rompe_el_aprovisionamiento(client):
    prov = _provider(collab_side_effect=Exception("404 usuario no existe"))
    r = _crear(client, prov, _payload(git_username="alice-gh"))
    assert r.status_code == 201
    assert r.json()["estado"] == "ACTIVO"
    assert r.json()["repo_url"] == REPO


# ---------- Fase 2: editar / borrar ----------

def _mapeo_con_repo(client, git_username="old-user", user_id=1, course_id=1, is_teacher=0):
    s = TestingSessionLocal()
    s.add(MapeoDB(moodle_user_id=user_id, moodle_course_id=course_id, repo_url=REPO,
                  matrix_room_id=f"!r{course_id}:x", estado="ACTIVO",
                  is_teacher=is_teacher, git_username=git_username))
    s.commit()
    s.close()


def _git_username_en_bd(course_id=1):
    s = TestingSessionLocal()
    try:
        return s.query(MapeoDB).filter(MapeoDB.moodle_course_id == course_id).one().git_username
    finally:
        s.close()


def test_put_cambia_usuario_revoca_el_anterior_y_anade_el_nuevo(client):
    _mapeo_con_repo(client, "old-user")
    prov = _provider()
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "new-user"})
    assert r.status_code == 200
    assert r.json() == {"git_username": "new-user", "repos_updated": 1, "errors": []}
    prov.eliminar_colaborador.assert_awaited_once_with(REPO, "old-user")
    prov.añadir_colaborador.assert_awaited_once_with(REPO, "new-user", "push")
    assert _git_username_en_bd() == "new-user"


def test_put_sin_usuario_anterior_solo_anade(client):
    _mapeo_con_repo(client, None)
    prov = _provider()
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "new-user"})
    assert r.status_code == 200
    prov.eliminar_colaborador.assert_not_awaited()
    assert _git_username_en_bd() == "new-user"


def test_put_mismo_usuario_no_lo_revoca(client):
    _mapeo_con_repo(client, "Same-User")
    prov = _provider()
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "same-user"})
    assert r.status_code == 200
    prov.eliminar_colaborador.assert_not_awaited()


def test_put_usuario_inexistente_devuelve_404_y_no_toca_nada(client):
    _mapeo_con_repo(client, "old-user")
    prov = _provider(exists=False)
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "no-existe"})
    assert r.status_code == 404
    prov.eliminar_colaborador.assert_not_awaited()
    prov.añadir_colaborador.assert_not_awaited()
    assert _git_username_en_bd() == "old-user"


def test_put_usuario_invalido_devuelve_422(client):
    prov = _provider()
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "a/b"})
    assert r.status_code == 422


def test_put_sin_mapeos_devuelve_ok_con_cero_repos(client):
    prov = _provider()
    r = _llamar(client, prov, "PUT", "/v1/usuarios/99/git-username", json={"git_username": "new-user"})
    assert r.status_code == 200
    assert r.json()["repos_updated"] == 0


def test_put_no_toca_mapeos_de_profesor(client):
    _mapeo_con_repo(client, None, is_teacher=1)
    prov = _provider()
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "new-user"})
    assert r.status_code == 200
    assert r.json()["repos_updated"] == 0
    prov.añadir_colaborador.assert_not_awaited()


def test_put_error_parcial_se_reporta_y_conserva_el_anterior(client):
    _mapeo_con_repo(client, "old-user")
    prov = _provider()
    prov.eliminar_colaborador = AsyncMock(side_effect=Exception("HTTP 500"))
    r = _llamar(client, prov, "PUT", "/v1/usuarios/1/git-username", json={"git_username": "new-user"})
    assert r.status_code == 200
    assert r.json()["repos_updated"] == 0 and len(r.json()["errors"]) == 1
    assert _git_username_en_bd() == "old-user"


def test_delete_revoca_y_limpia(client):
    _mapeo_con_repo(client, "old-user")
    prov = _provider()
    r = _llamar(client, prov, "DELETE", "/v1/usuarios/1/git-username")
    assert r.status_code == 200
    assert r.json() == {"git_username": None, "repos_updated": 1, "errors": []}
    prov.eliminar_colaborador.assert_awaited_once_with(REPO, "old-user")
    assert _git_username_en_bd() is None


def test_delete_es_idempotente_sin_usuario(client):
    _mapeo_con_repo(client, None)
    prov = _provider()
    r = _llamar(client, prov, "DELETE", "/v1/usuarios/1/git-username")
    assert r.status_code == 200
    assert r.json()["repos_updated"] == 0
    prov.eliminar_colaborador.assert_not_awaited()


def test_endpoints_requieren_token(client):
    assert client.put("/v1/usuarios/1/git-username", json={"git_username": "x"}).status_code in (401, 403)
    assert client.delete("/v1/usuarios/1/git-username").status_code in (401, 403)


def test_normalize_git_username():
    assert normalize_git_username("@abc") == "abc"
    assert normalize_git_username("  ab-c_d.e ") == "ab-c_d.e"
    for bad in (None, "", "   ", "-abc", "abc-", "a b", "a/b", "../x", "a" * 300):
        assert normalize_git_username(bad) is None
