<?php
/**
 * Block for LLM Wiki Assistant (BdC).
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

class block_bdc extends block_base {
    
    /**
     * Initialize the block properties.
     */
    public function init() {
        $this->title = get_string('pluginname', 'block_bdc');
    }

    /**
     * Define the formats where this block can be added.
     *
     * @return array
     */
    public function applicable_formats() {
        return [
            'all' => true,
        ];
    }

    /**
     * Allow multiple instances of this block.
     *
     * @return bool
     */
    public function instance_allow_multiple() {
        return true;
    }

    /**
     * Get the block content.
     *
     * @return stdClass|string
     */
    public function get_content() {
        if ($this->content !== null) {
            return $this->content;
        }

        $this->content = new stdClass;
        $this->content->text   = '';
        $this->content->footer = '';

        if (empty($this->instance) || !isloggedin() || isguestuser()) {
            return $this->content;
        }

        $courseid = $this->page->course->id;

        $url = new moodle_url('/blocks/bdc/view.php', ['courseid' => $courseid]);
        $btn_text = get_string('btn_access', 'block_bdc');

        $this->content->text = \html_writer::tag('div',
            \html_writer::link($url, $btn_text, ['class' => 'btn btn-primary w-100']),
            ['class' => 'text-center p-3']
        );

        // Estado del usuario de GitHub (alumnos y profesores; no es crítico: nunca debe romper el bloque).
        try {
            // El nombre de la preferencia es el mismo que usan view.php y github_username.php.
            $ghuser = (string)get_user_preferences('block_bdc_github_username', '');
            $ghurl = new moodle_url('/blocks/bdc/github_username.php', ['courseid' => $courseid]);
            if ($ghuser !== '') {
                $msg = get_string('github_current', 'block_bdc', s($ghuser));
                $linktext = get_string('github_edit', 'block_bdc');
            } else {
                $msg = get_string('github_not_set', 'block_bdc');
                $linktext = get_string('github_set', 'block_bdc');
            }
            $this->content->text .= \html_writer::tag('div',
                \html_writer::tag('div', $msg, ['class' => 'small text-muted']) .
                \html_writer::link($ghurl, $linktext, ['class' => 'small']),
                ['class' => 'text-center pb-3']
            );
        } catch (\Throwable $e) {
            debugging('block_bdc: no se pudo mostrar el usuario de GitHub: ' . $e->getMessage(), DEBUG_DEVELOPER);
        }

        return $this->content;
    }
}
