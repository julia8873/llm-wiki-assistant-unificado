<?php
/**
 * Event observers for block_bdc.
 *
 * @package   block_bdc
 * @copyright 2026 LLM Wiki Assistant
 * License:   http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

defined('MOODLE_INTERNAL') || die();

$observers = array(
    array(
        'eventname'   => '\\core\\event\\course_created',
        'callback'    => 'block_bdc\\observer::course_created',
    ),
    array(
        'eventname'   => '\\core\\event\\user_enrolment_created',
        'callback'    => 'block_bdc\\observer::user_enrolment_created',
    ),
    array(
        'eventname'   => '\\core\\event\\role_assigned',
        'callback'    => 'block_bdc\\observer::role_assigned',
    ),
);
