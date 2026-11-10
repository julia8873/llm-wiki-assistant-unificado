<?php
/**
 * Language strings for block_bdc.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

defined('MOODLE_INTERNAL') || die();

$string['pluginname'] = 'Mi asistente BdC';
$string['bdc'] = 'Base de Conocimiento (IA)';
$string['bdc:addinstance'] = 'Add a new BdC block';
$string['bdc:myaddinstance'] = 'Add a new BdC block to the My Moodle page';
$string['btn_access'] = 'Acceder a mi sala con el Asistente IA';
$string['creating_room'] = 'Creando sala... por favor espera.';
$string['error_mapping'] = 'Ocurrió un error al vincular la sala. Contacta con soporte.';

// Usuario de GitHub del alumno.
$string['github_title'] = 'Mi usuario de GitHub';
$string['github_intro'] = 'Indica tu usuario de GitHub para que se te añada como colaborador de tu repositorio de la asignatura. Recibirás una invitación de GitHub que deberás aceptar. Si lo dejas vacío y guardas, se revocará tu acceso.';
$string['github_field'] = 'Usuario de GitHub';
$string['github_field_desc'] = 'Solo el nombre de usuario, por ejemplo: octocat (sin URL).';
$string['github_current'] = 'Usuario de GitHub: {$a}';
$string['github_not_set'] = 'Aún no has indicado tu usuario de GitHub.';
$string['github_set'] = 'Indicar usuario de GitHub';
$string['github_edit'] = 'Cambiar o eliminar';
$string['github_delete'] = 'Eliminar mi usuario de GitHub';
$string['github_delete_confirm'] = 'Se revocará tu acceso como colaborador a tus repositorios. ¿Continuar?';
$string['github_saved'] = 'Usuario de GitHub guardado. Revisa tu correo o GitHub para aceptar la invitación al repositorio.';
$string['github_deleted'] = 'Usuario de GitHub eliminado y acceso revocado.';
$string['github_partial'] = 'Cambio guardado, pero no se pudo actualizar el acceso en {$a} repositorio(s). Inténtalo de nuevo más tarde o contacta con soporte.';
$string['github_invalid'] = 'Nombre de usuario no válido. Usa solo letras, números, guiones, puntos o guiones bajos.';
$string['error_github_invalid'] = 'El nombre de usuario de GitHub no es válido.';
$string['error_github_not_found'] = 'El usuario de GitHub indicado no existe.';
$string['error_github_sync'] = 'No se pudo actualizar el usuario de GitHub (HTTP {$a}). Inténtalo de nuevo más tarde.';

// Privacidad.
$string['privacy:metadata:preference:github_username'] = 'El usuario de GitHub que el alumno ha indicado para ser añadido como colaborador de su repositorio.';
$string['privacy:metadata:mapeo_api'] = 'Para aprovisionar los repositorios y salas se envían datos a la API de mapeo.';
$string['privacy:metadata:mapeo_api:moodle_user_id'] = 'El ID del usuario en Moodle.';
$string['privacy:metadata:mapeo_api:moodle_username'] = 'El nombre de usuario en Moodle, usado para nombrar el repositorio y la sala.';
$string['privacy:metadata:mapeo_api:git_username'] = 'El usuario de GitHub indicado por el alumno, usado para darle acceso a su repositorio.';
