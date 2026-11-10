import pytest
import respx

from app.services.git.github_provider import GitHubProvider, GitHubProvisionError


@pytest.fixture
def base_config():
    return {
        'git': {
            'github': {
                'organizacion': 'test-org',
                'repo_plantilla': 'test-template',
                'api_base_url': 'https://api.github.com',
                'pat': 'test-pat-123',
                'pat_env_var': 'GITHUB_PAT'
            }
        }
    }


BASE = "https://api.github.com/repos/test-org/Math101-studentA"


@pytest.mark.asyncio
@respx.mock
async def test_eliminar_colaborador_y_cancelar_invitacion_pendiente(base_config):
    provider = GitHubProvider(base_config)
    del_collab = respx.delete(f"{BASE}/collaborators/alice").respond(status_code=204)
    respx.get(f"{BASE}/invitations").respond(
        status_code=200,
        json=[{"id": 7, "invitee": {"login": "Alice"}}, {"id": 8, "invitee": {"login": "otro"}}]
    )
    del_inv7 = respx.delete(f"{BASE}/invitations/7").respond(status_code=204)
    del_inv8 = respx.delete(f"{BASE}/invitations/8").respond(status_code=204)

    await provider.eliminar_colaborador("https://github.com/test-org/Math101-studentA.git", "alice")

    assert del_collab.called
    assert del_inv7.called
    assert not del_inv8.called


@pytest.mark.asyncio
@respx.mock
async def test_eliminar_colaborador_inexistente_es_idempotente(base_config):
    provider = GitHubProvider(base_config)
    respx.delete(f"{BASE}/collaborators/alice").respond(status_code=404)
    respx.get(f"{BASE}/invitations").respond(status_code=200, json=[])

    await provider.eliminar_colaborador("Math101-studentA", "alice")


@pytest.mark.asyncio
@respx.mock
async def test_eliminar_colaborador_error_se_propaga(base_config):
    provider = GitHubProvider(base_config)
    respx.delete(f"{BASE}/collaborators/alice").respond(status_code=500)

    with pytest.raises(GitHubProvisionError):
        await provider.eliminar_colaborador("Math101-studentA", "alice")


@pytest.mark.asyncio
@respx.mock
async def test_usuario_existe(base_config):
    provider = GitHubProvider(base_config)
    respx.get("https://api.github.com/users/alice").respond(status_code=200, json={"login": "alice"})
    respx.get("https://api.github.com/users/ghost-xyz").respond(status_code=404)
    respx.get("https://api.github.com/users/boom").respond(status_code=500)

    assert await provider.usuario_existe("alice") is True
    assert await provider.usuario_existe("ghost-xyz") is False
    with pytest.raises(GitHubProvisionError):
        await provider.usuario_existe("boom")
