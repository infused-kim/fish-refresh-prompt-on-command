#
# Explanations
#
# A few notes about how fish works:
#
#   - When a command is entered,
#     - The binding `bind --preset \n __rpoc_custom_event_enter_pressed` is
#       executed first
#     - Then the event `fish_preexec` is fired, but only if the command is not
#       empty
#     - Then the command is executed and no events fire during that execution
#     - Then the event `fish_postexec` is fired, but only if the command is not
#       empty
#     - Then the event `fish_prompt` is fired
#     - Once all `fish_prompt` _events_ finish processing, then the prompt
#       _function_ `fish_prompt` is called
#     - Once it finishes, the prompt function `fish_right_prompt` is called
#
#   - About the `fish_preexec` and `fish_postexec` events:
#     - Only fired if the command is not empty
#     - The `commandline -f repaint` command does NOT work in `fish_preexec`
#     - Instead the keybind hack must be used if you want to refresh the prompt
#       before a command is executed
#
#   - About the `--on-event fish_prompt` event:
#     - Only fired when the shell is starting up and after a command
#     - NOT fired on `commandline -f repaint`
#
# Thefore...
#   - We bind the enter key to a custom event function that triggers the
#     repaint on enter.
#   - We also set the variable `rpoc_is_refreshing` to 1 to indicate that we
#     are in refresh mode.
#   - We also replace the original prompt functions and then set
#     `rpoc_is_refreshing` to 0 once the prompt is rendered (after the
#     fish_right_prompt function finishes)


# Setup function that is run ONCE when the shell starts up,
# just before the first prompt is displayed
function __rpoc_setup_on_startup --on-event fish_prompt

    # Removes this function after it runs once, since it only needs to run on
    # startup
    functions -e (status current-function)

    # Don't run if the shell is not interactive
    status is-interactive
    or exit 0

    __rpoc_log (status current-function) "Starting setup"

    # Create variable to track if we are in pre-exec mode
    set -g rpoc_is_refreshing 0

    # Create variables to store prompt backups that are used
    # when rpoc_disable_refresh_left or rpoc_disable_refresh_right is enabled
    set -g __rpoc_prompt_backup_left ''
    set -g __rpoc_prompt_backup_right ''

    # Bind enter key to custom event function
    bind --preset \n __rpoc_custom_event_enter_pressed
    bind --preset \r __rpoc_custom_event_enter_pressed

    # Backup and replace prompt functions if they exist
    if functions -q fish_prompt
        functions -c fish_prompt '__rpoc_orig_fish_prompt'
        functions -e fish_prompt
        functions -c __rpoc_fish_prompt fish_prompt
    else
        # If fish_prompt doesn't exist, just create our function
        functions -c __rpoc_fish_prompt fish_prompt
    end

    if functions -q fish_right_prompt
        functions -c fish_right_prompt '__rpoc_orig_fish_right_prompt'
        functions -e fish_right_prompt
        functions -c __rpoc_fish_right_prompt fish_right_prompt
    else
        # If fish_right_prompt doesn't exist, check if the default right
        # time prompt should be used
        if not __rpoc_is_config_enabled_time_prompt_disabled
            functions -c rpoc_fish_right_prompt_time '__rpoc_orig_fish_right_prompt'
        end
        functions -c __rpoc_fish_right_prompt fish_right_prompt
    end

    __rpoc_log "Setup complete"
end


# Executed whenever the enter key is pressed.
#
# Sets our tracking variable `rpoc_is_refreshing` to 1 and asks fish to
# repaint the prompt before the new command is executed.
function __rpoc_custom_event_enter_pressed
    __rpoc_log "Started"

    __rpoc_log "Setting rpoc_is_refreshing to 1"

    # Set the variable to 1 to indicate that next prompt repaint is in fact
    # a refresh
    set -g rpoc_is_refreshing 1

    __rpoc_log "Executing repaint"

    # This is what actually repaints the prompt and causes the
    # `fish_prompt` and `fish_right_prompt` functions to be called again.
    #
    # But the `fish_prompt` event is NOT fired.
    commandline -f repaint

    __rpoc_log "Executing cmd execute"

    # This makes sure the command is executed, but it doesn't actually execute
    # the command at this point. It just tells the shell that we do want to
    # execute the command.
    #
    # Before it's executed, the prompt is repainted (due to the repaint cmd),
    # the preexec events are fired, etc.
    commandline -f execute

    __rpoc_log "Finished"

end


# Wrapper functions for the original prompt functions that are called during
# prompt rendering as well as re-rendering on refresh.
function __rpoc_fish_prompt
    __rpoc_log "Starting fish_prompt wrapper"

    if test "$rpoc_is_refreshing" = 1; and __rpoc_is_config_enabled_disable_refresh_left
        __rpoc_log "Refresh disabled, using backup prompt"
        echo -n $__rpoc_prompt_backup_left
    else
        __rpoc_log "Running original fish_prompt"

        # Run the original prompt function if it exists, otherwise use empty prompt
        set -l prompt_output
        if functions -q __rpoc_orig_fish_prompt
            set prompt_output (rpoc_is_refreshing=$rpoc_is_refreshing __rpoc_orig_fish_prompt)
        end

        # Store backup of the prompt
        set -g __rpoc_prompt_backup_left $prompt_output

        # Output the prompt
        echo -n $prompt_output
    end

    __rpoc_log "Finished"
end

function __rpoc_fish_right_prompt
    __rpoc_log "Running fish_right_prompt wrapper"

    if test "$rpoc_is_refreshing" = 1; and __rpoc_is_config_enabled_disable_refresh_right
        __rpoc_log "Refresh disabled, using backup prompt"
        echo -n $__rpoc_prompt_backup_right
    else
        __rpoc_log "Running original fish_right_prompt"

        # Run the original prompt function if it exists, otherwise use empty prompt
        set -l prompt_output
        if functions -q __rpoc_orig_fish_right_prompt
            set prompt_output (rpoc_is_refreshing=$rpoc_is_refreshing __rpoc_orig_fish_right_prompt)
        end

        # Store backup of the prompt
        set -g __rpoc_prompt_backup_right $prompt_output

        # Output the prompt
        echo -n $prompt_output
    end

    __rpoc_log "Running __rpoc_custom_event_post_prompt_rendering"

    # Run custom event after prompt is rendered
    __rpoc_custom_event_post_prompt_rendering

    __rpoc_log "Finished"
end

# Called by our fish_right_prompt wrapper function after the prompt is fully
# rendered and before the command is executed.
function __rpoc_custom_event_post_prompt_rendering
    __rpoc_log "Setting rpoc_is_refreshing to 0"

    # Reset the variable to 0 to indicate that the next prompt repaint is not a
    # refresh
    set -g rpoc_is_refreshing 0

    __rpoc_log "Finished"
end


#
# Time Prompt
#

# Prints `at --:--:--` when rpoc_is_refreshing == 0
# and `at 18:56:04` when rpoc_is_refreshing == 1
#
# Can be customized with the following config variables:
# set -g rpoc_time_prompt_time_color green
# set -g rpoc_time_prompt_prefix 'time: '
# set -g rpoc_time_prompt_prefix_color red
# set -g rpoc_time_prompt_postfix ' wow ⏰'
# set -g rpoc_time_prompt_postfix_color magenta
#
function rpoc_fish_right_prompt_time
    # Get prefix from config or use default
    set -l prefix
    if set -q rpoc_time_prompt_prefix
        set prefix $rpoc_time_prompt_prefix
    else
        set prefix "at "
    end

    # Get prefix color from config or use default (normal)
    set -l prefix_color
    if set -q rpoc_time_prompt_prefix_color
        set prefix_color $rpoc_time_prompt_prefix_color
    else
        set prefix_color normal
    end

    # Get time color from config or use default (yellow)
    set -l time_color
    if set -q rpoc_time_prompt_time_color
        set time_color $rpoc_time_prompt_time_color
    else
        set time_color yellow
    end

    # Get postfix from config or use default (empty)
    set -l postfix
    if set -q rpoc_time_prompt_postfix
        set postfix $rpoc_time_prompt_postfix
    else
        set postfix ""
    end

    # Get postfix color from config or use default (normal)
    set -l postfix_color
    if set -q rpoc_time_prompt_postfix_color
        set postfix_color $rpoc_time_prompt_postfix_color
    else
        set postfix_color normal
    end

    if test -n "$rpoc_is_refreshing" -a "$rpoc_is_refreshing" = "1" 2>/dev/null
        set_color $prefix_color
        echo -n $prefix
        set_color --bold $time_color
        echo -n (date "+%H:%M:%S")
        set_color $postfix_color
        echo -n $postfix
        set_color normal
    else
        set_color $prefix_color
        echo -n $prefix
        set_color --bold $time_color
        echo -n "--:--:--"
        set_color $postfix_color
        echo -n $postfix
        set_color normal
    end
end


#
# Command Duration
#

function __rpoc_cmd_duration_postexec --on-event fish_postexec
    __rpoc_cmd_duration $CMD_DURATION
end

function __rpoc_cmd_duration --argument-names seconds
    # Check if duration display is disabled
    if __rpoc_is_config_enabled_cmd_duration_disabled
        return
    end

    # Only show duration for commands that took longer than 3 seconds
    if not set -q seconds[1]; or test -z "$seconds"; or test $seconds -lt 3000
        return
    end

    # Get prefix from config or use default
    set -l prefix
    if set -q rpoc_cmd_duration_prefix
        set prefix $rpoc_cmd_duration_prefix
    else
        set prefix "⌛ took "
    end

    # Get prefix color from config or use default (normal)
    set -l prefix_color
    if set -q rpoc_cmd_duration_prefix_color
        set prefix_color $rpoc_cmd_duration_prefix_color
    else
        set prefix_color normal
    end

    # Get duration color from config or use default (yellow)
    set -l duration_color
    if set -q rpoc_cmd_duration_time_color
        set duration_color $rpoc_cmd_duration_time_color
    else
        set duration_color yellow
    end

    # Get postfix from config or use default (empty)
    set -l postfix
    if set -q rpoc_cmd_duration_postfix
        set postfix $rpoc_cmd_duration_postfix
    else
        set postfix ""
    end

    # Get postfix color from config or use default (normal)
    set -l postfix_color
    if set -q rpoc_cmd_duration_postfix_color
        set postfix_color $rpoc_cmd_duration_postfix_color
    else
        set postfix_color normal
    end

    set -l duration_str (__rpoc_convert_seconds_to_duration $seconds 0)

    echo ''
    set_color $prefix_color
    echo -n $prefix
    set_color --bold $duration_color
    echo -n $duration_str
    set_color $postfix_color
    echo -n $postfix
    set_color normal
end

function __rpoc_convert_seconds_to_duration --argument-names seconds decimals
    set -q decimals[1]; or set decimals 0

    set -l t (
        math -s0 "$seconds/3600000" # Hours
        math -s0 "$seconds/60000"%60 # Minutes
        math -s$decimals "$seconds/1000"%60
    )

    set -l duration_str
    if test $t[1] != 0
        set duration_str "$t[1]h $t[2]m $t[3]s"
    else if test $t[2] != 0
        set duration_str "$t[2]m $t[3]s"
    else
        set duration_str "$t[3]s"
    end

    echo $duration_str
end


#
# Logging
#

# Logs a message to the debug log file if `__rpoc_debug` is set to `1`.
function __rpoc_log --argument-names message
    if test "$__rpoc_debug" = 1
        # Initialize debug log file in XDG cache dir or ~/.cache if not already done
        if not set -q __rpoc_debug_log
            set -l cache_dir
            if set -q XDG_CACHE_HOME
                set cache_dir "$XDG_CACHE_HOME/fish"
            else
                set cache_dir "$HOME/.cache/fish"
            end
            mkdir -p "$cache_dir"
            set -g __rpoc_debug_log "$cache_dir/fish_refresh_prompt_on_cmd.log"
        end

        set -l prev_func_name (__rpoc_get_prev_func_name)
        echo (date "+%Y-%m-%d %H:%M:%S") "[$prev_func_name] $message (is_refreshing: $rpoc_is_refreshing)" >> $__rpoc_debug_log
    end
end


# Returns the name of the function that called the function that
# calls this function.
#
# Used in the debug log to print the name of the function that is logging
# the message.
function __rpoc_get_prev_func_name
    set -l stack_lines
    for line in (status stack-trace)
        if string match -q 'in function*' "$line"
            set -a stack_lines "$line"
        end
    end

    # We want the prev function of the caller
    # Fish arrays start at index 1, current function is 1, caller is 2,
    # caller of caller is 3 (what we want)
    set -l caller_line $stack_lines[3]

    # Extract function name from "in function 'name'" pattern from caller_line

    set -l caller (string match -gr "in function '([^\']+)'" "$caller_line")
    if test -z "$caller"
        set caller 'unknown-function'
    end

    echo $caller
end


# These fish events are not actually used and simply serve to debug fish events
# when `rpoc_debug` is enabled

function __rpoc_on_event_fish_prompt --on-event fish_prompt
    __rpoc_log "Fired"
end

function __rpoc_postexec --on-event fish_postexec
    __rpoc_log "Fired"
end

function __rpoc_preexec --on-event fish_preexec
    __rpoc_log "Fired"
end

#
# Settings
#
# Settings return 0 when enabled and 1 when disabled due to shell convention
# that 0 is success and 1 is failure. This allows us to check if it's enabled
# without a comparison.


# rpoc_cmd_duration_disabled is used to disable the command duration display
function __rpoc_is_config_enabled_cmd_duration_disabled
    __rpoc_is_config_enabled rpoc_cmd_duration_disabled
    return $status
end


# rpoc_disable_refresh_left is used to disable the refresh of the left prompt
function __rpoc_is_config_enabled_disable_refresh_left
    __rpoc_is_config_enabled rpoc_disable_refresh_left
    return $status
end


# rpoc_disable_refresh_right is used to disable the refresh of the right prompt
function __rpoc_is_config_enabled_disable_refresh_right
    __rpoc_is_config_enabled rpoc_disable_refresh_right
    return $status
end


# Check if a config variable is enabled
function __rpoc_is_config_enabled --argument-names var_name
    if not set -q $var_name
        return 1
    end
    set -l value (string lower $$var_name)
    if test -z "$value" # empty string
        return 1
    end
    switch "$value"
        case 1 true
            return 0
        case 0 false
            return 1
        case '*'
            return 1
    end
end


# rpoc_time_prompt_disabled is used to disable the time prompt when no right prompt exists
function __rpoc_is_config_enabled_time_prompt_disabled
    __rpoc_is_config_enabled rpoc_time_prompt_disabled
    return $status
end
