<?php
/**
 * Privacy provider for block_bdc.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

namespace block_bdc\privacy;

defined('MOODLE_INTERNAL') || die();

use core_privacy\local\metadata\collection;
use core_privacy\local\request\writer;

class provider implements
    \core_privacy\local\metadata\provider,
    \core_privacy\local\request\user_preference_provider {

    /**
     * Describe los datos que guarda y envía el plugin.
     *
     * @param collection $collection
     * @return collection
     */
    public static function get_metadata(collection $collection): collection {
        $collection->add_user_preference('block_bdc_github_username', 'privacy:metadata:preference:github_username');
        $collection->add_external_location_link('mapeo_api', [
            'moodle_user_id' => 'privacy:metadata:mapeo_api:moodle_user_id',
            'moodle_username' => 'privacy:metadata:mapeo_api:moodle_username',
            'git_username' => 'privacy:metadata:mapeo_api:git_username',
        ], 'privacy:metadata:mapeo_api');
        return $collection;
    }

    /**
     * Exporta las preferencias del usuario.
     *
     * @param int $userid
     */
    public static function export_user_preferences(int $userid) {
        $value = get_user_preferences('block_bdc_github_username', null, $userid);
        if ($value !== null) {
            writer::export_user_preference(
                'block_bdc',
                'block_bdc_github_username',
                $value,
                get_string('privacy:metadata:preference:github_username', 'block_bdc')
            );
        }
    }
}
