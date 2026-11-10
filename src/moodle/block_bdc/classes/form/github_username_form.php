<?php
/**
 * Formulario para indicar el usuario de GitHub del alumno.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

namespace block_bdc\form;

defined('MOODLE_INTERNAL') || die();

require_once($CFG->libdir . '/formslib.php');

class github_username_form extends \moodleform {

    /**
     * Define los campos del formulario.
     */
    protected function definition() {
        $mform = $this->_form;

        $mform->addElement('text', 'githubusername', get_string('github_field', 'block_bdc'), ['size' => 40, 'maxlength' => 100]);
        $mform->setType('githubusername', PARAM_TEXT);
        $mform->addElement('static', 'githubusernamedesc', '', get_string('github_field_desc', 'block_bdc'));

        $this->add_action_buttons(true, get_string('savechanges'));
    }

    /**
     * Valida el formato del usuario (vacío = eliminar).
     *
     * @param array $data
     * @param array $files
     * @return array
     */
    public function validation($data, $files) {
        $errors = parent::validation($data, $files);
        $value = ltrim(trim($data['githubusername'] ?? ''), '@');
        if ($value !== '' && !preg_match('/^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,253}[A-Za-z0-9])?$/', $value)) {
            $errors['githubusername'] = get_string('github_invalid', 'block_bdc');
        }
        return $errors;
    }
}
