# Beautified gum/zellij "which session?" launcher shown on interactive SSH login.
#
# - On SSH login the user gets a Catppuccin-Macchiato gum TUI: a list of existing
#   zellij sessions (with their agent) plus "+ New session". Creating one asks for a
#   name and whether to run the Claude or the Pi agent; the session's first tab is
#   named after the session and runs that agent.
# - Agents are launched with a system prompt taken from the Nix config
#   (programs.lani.menu.systemPrompt), so the prompt is parametrized declaratively.
# - The menu `exec`s over the login shell and ends right after the zellij client
#   returns, so detaching the session (Ctrl-o d) drops the SSH connection.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lani.menu;

  systemPromptFile = pkgs.writeText "agent-system-prompt.txt" cfg.systemPrompt;
  promptFlag = if cfg.replaceSystemPrompt then "--system-prompt" else "--append-system-prompt";

  # Per-agent launchers that bake in the parametrized system prompt. zellij runs
  # these directly (via the layout), so there is no nested-quoting to get wrong.
  # Ensure all launchers inherit the full system PATH so tools like `nix` are
  # reachable from agent sessions (zellij strips PATH to nix-store entries).
  sysPath = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin";

  # Entries are only forced when the name appears in cfg.agents, which keeps the unfree
  # claude-code out of the closure unless asked for.
  agentSpecs = {
    pi = {
      label = "Pi coding agent";
      launcher = pkgs.writeShellScript "agent-pi" ''
        export PATH="${sysPath}:$PATH"
        exec ${pkgs.pi-coding-agent}/bin/pi ${promptFlag} "$(cat ${systemPromptFile})" "$@"
      '';
    };
    opencode = {
      label = "opencode agent";
      # opencode has no prompt flag, so lani.shell.systemPrompt is not applied to it.
      launcher = pkgs.writeShellScript "agent-opencode" ''
        export PATH="${sysPath}:$PATH"
        exec ${pkgs.opencode}/bin/opencode "$@"
      '';
    };
    claude = {
      label = "Anthropic Claude Code";
      launcher = pkgs.writeShellScript "agent-claude" ''
        export PATH="${sysPath}:$PATH"
        exec ${pkgs.claude-code}/bin/claude ${promptFlag} "$(cat ${systemPromptFile})" "$@"
      '';
    };
    shell = {
      label = "Plain interactive shell";
      launcher = pkgs.writeShellScript "agent-shell" ''
        export PATH="${sysPath}:$PATH"
        exec ${pkgs.zsh}/bin/zsh -l
      '';
    };
  };

  selectedAgents = lib.filter (a: agentSpecs ? ${a}) cfg.agents;

  launcherCase = lib.concatMapStringsSep "\n" (
    a: "            ${a}) launcher=${agentSpecs.${a}.launcher} ;;"
  ) selectedAgents;

  menuRows = lib.concatMapStringsSep "\n" (
    a: ''"${lib.fixedWidthString 9 " " a}— ${agentSpecs.${a}.label}" \''
  ) selectedAgents;

  # Non-interactive launcher driven by the web sidebar (via ttyd's URL args, -a):
  #   web-term-launch attach <name>            -> attach an existing session
  #   web-term-launch create <name> <agent>    -> create+attach a new one
  # It writes the SAME state (agent marker + per-session layout) as the gum menu's
  # create_session, so sessions made from the web and over SSH are interchangeable.
  webTermLauncher = pkgs.writeShellApplication {
    name = "web-term-launch";
    runtimeInputs = [
      pkgs.zellij
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
            set -uo pipefail
            mode="''${1:-}"; name="''${2:-}"; agent="''${3:-}"
            state="''${XDG_STATE_HOME:-$HOME/.local/state}/agent-menu"
            mkdir -p "$state/sessions" "$state/layouts"

            case "$mode" in
              attach)
                [ -n "$name" ] || { echo "no session given"; sleep 2; exit 1; }
                # Use exec so a service restart (rebuild) doesn't kill the session.
                # Sessions are cleaned up explicitly via the sidebar × button.
                exec zellij attach "$name"
                ;;
              create)
                name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9_-' '_' | sed 's/_*$//')"
                [ -n "$name" ] || { echo "bad session name"; sleep 2; exit 1; }
                case "$agent" in
      ${launcherCase}
                  *)        echo "unknown agent: $agent"; sleep 2; exit 1 ;;
                esac
                printf '%s' "$agent" > "$state/sessions/$name"
                layout="$state/layouts/$name.kdl"
                {
                  echo 'layout {'
                  echo '    default_tab_template {'
                  echo '        pane size=1 borderless=true { plugin location="zellij:tab-bar"; }'
                  echo '        children'
                  echo '    }'
                  echo "    tab name=\"$name\" focus=true {"
                  echo "        pane command=\"$launcher\""
                  echo '    }'
                  echo '}'
                } > "$layout"
                exec zellij --session "$name" --new-session-with-layout "$layout"
                ;;
              install)
                [ -n "''${2:-}" ] || { echo "no module name given"; sleep 2; exit 1; }
                module="''${2:-}"
                session="lani-''${module}"
                launcher="$(mktemp /tmp/lani-install-XXXXXX.sh)"
                {
                  # Absolute shebang: zellij runs this as a pane command with a PATH
                  # stripped to nix-store entries, so `/usr/bin/env bash` can't resolve
                  # bash (the export below runs too late). Point straight at the store.
                  echo '#!${pkgs.bash}/bin/bash'
                  # shellcheck disable=SC2016
                  printf 'export PATH=%s:$PATH\n' "${sysPath}"
                  # This pane's command runs from web-terminal.service, which — like any
                  # systemd service — does not inherit environment.variables (only login
                  # shells source /etc/set-environment). Over SSH LANI_CATALOG is already
                  # in the environment; here it has to be passed explicitly or `lani`
                  # dies with "LANI_CATALOG is not set".
                  printf 'export LANI_CATALOG=%s\n' "${config.programs.lani.webTerminal.catalogPath}"
                  printf 'lani modules use %s\n' "$module"
                  echo 'echo; read -rp "Installation complete. Press Enter. "'
                } > "$launcher"
                chmod +x "$launcher"
                printf '%s' "shell" > "$state/sessions/$session"
                layout="$state/layouts/$session.kdl"
                {
                  echo 'layout {'
                  echo '    default_tab_template {'
                  echo '        pane size=1 borderless=true { plugin location="zellij:tab-bar"; }'
                  echo '        children'
                  echo '    }'
                  echo "    tab name=\"$session\" focus=true {"
                  echo "        pane command=\"$launcher\""
                  echo '    }'
                  echo '}'
                } > "$layout"
                exec zellij --session "$session" --new-session-with-layout "$layout"
                ;;
              *)
                echo "Pick or create a session from the sidebar."
                sleep 3
                ;;
            esac
    '';
  };

  # zellij configuration: Catppuccin Macchiato + tidy UI. Pointed at by
  # ZELLIJ_CONFIG_DIR so it does not depend on the (encrypted) home.
  # - default_shell zsh: new tabs/panes (Ctrl-t n / Ctrl-p n) open zsh.
  # - mouse_mode true: the tab bar is clickable — click a tab to switch to it.
  zellijConfigDir = pkgs.writeTextDir "config.kdl" ''
    theme "catppuccin-macchiato"
    default_shell "${pkgs.zsh}/bin/zsh"
    mouse_mode true
    show_startup_tips false
    show_release_notes false
    // Don't serialize sessions to disk: when the last pane/tab of a session closes the
    // session is gone for good, rather than lingering as a resurrectable "EXITED" entry
    // in `zellij list-sessions` (and in the web/SSH menu).
    session_serialization false
    pane_frames true
    ui {
      pane_frames {
        rounded_corners true
      }
    }
    themes {
      catppuccin-macchiato {
        bg "#363a4f"
        fg "#cad3f5"
        red "#ed8796"
        green "#a6da95"
        blue "#8aadf4"
        yellow "#eed49f"
        magenta "#c6a0f6"
        orange "#f5a97f"
        cyan "#91d7e3"
        black "#1e2030"
        white "#cad3f5"
      }
    }
  '';

  agentMenu = pkgs.writeShellApplication {
    name = "agent-menu";
    # Keep this self-contained: writeShellApplication only puts runtimeInputs on PATH.
    # Over SSH the inherited login PATH masked two gaps — `awk` (gawk) and `clear`
    # (ncurses) — but a systemd service (the web terminal) has a stripped PATH, so the
    # menu must list every external binary it calls itself.
    runtimeInputs = [
      pkgs.gum
      pkgs.zellij
      pkgs.coreutils
      pkgs.gnused
      pkgs.gawk
      pkgs.ncurses
    ];
    text = ''
            set -uo pipefail

            # ---- Catppuccin Macchiato palette (the shades this menu actually uses) ----
            text="#cad3f5"; subtext="#a5adcb"; overlay="#6e738d"
            mauve="#c6a0f6"; blue="#8aadf4"; green="#a6da95"; peach="#f5a97f"; lavender="#b7bee8"

            # ---- Theme gum globally so every prompt matches ----
            export GUM_CHOOSE_CURSOR="❯ "
            export GUM_CHOOSE_CURSOR_FOREGROUND="$mauve"
            export GUM_CHOOSE_HEADER_FOREGROUND="$blue"
            export GUM_CHOOSE_SELECTED_FOREGROUND="$lavender"
            export GUM_CHOOSE_ITEM_FOREGROUND="$text"
            export GUM_INPUT_PROMPT_FOREGROUND="$mauve"
            export GUM_INPUT_CURSOR_FOREGROUND="$peach"
            export GUM_INPUT_HEADER_FOREGROUND="$blue"
            export GUM_SPIN_SPINNER_FOREGROUND="$mauve"
            export GUM_SPIN_TITLE_FOREGROUND="$subtext"

            state="''${XDG_STATE_HOME:-$HOME/.local/state}/agent-menu"
            mkdir -p "$state/sessions" "$state/layouts"

            banner() {
              clear || true
              gum style --border rounded --border-foreground "$mauve" \
                --foreground "$text" --padding "0 3" --margin "1 0 0 1" --align center \
                "🤖 lani" "$(gum style --foreground "$overlay" "session manager")"
            }

            strip_ansi() { sed -r 's/\x1b\[[0-9;]*m//g'; }

            list_session_names() {
              # plain session names, newest-ish order; tolerate "no sessions"
              zellij list-sessions -s 2>/dev/null | strip_ansi | awk 'NF{print $1}'
            }

            agent_of() { cat "$state/sessions/$1" 2>/dev/null || echo "?"; }

            create_session() {
              local name agent launcher layout
              name="$(gum input --header "Name your new session" --placeholder "my-feature" --prompt "❯ ")"
              name="$(printf '%s' "''${name:-}" | tr -c 'A-Za-z0-9_-' '_' | sed 's/_*$//')"
              [ -z "$name" ] && return 1

              agent="$(printf '%s\n' \
      ${menuRows}
                | gum choose --header "What runs in '$name'?" | awk '{print $1}')"
              case "''${agent:-}" in
      ${launcherCase}
                *)        return 1 ;;
              esac
              printf '%s' "$agent" > "$state/sessions/$name"

              # First tab is named after the session and runs the chosen agent.
              layout="$state/layouts/$name.kdl"
              {
                echo 'layout {'
                echo '    default_tab_template {'
                echo '        pane size=1 borderless=true { plugin location="zellij:tab-bar"; }'
                echo '        children'
                echo '    }'
                echo "    tab name=\"$name\" focus=true {"
                echo "        pane command=\"$launcher\""
                echo '    }'
                echo '}'
              } > "$layout"

              gum spin --title "Spinning up '$name' ($agent)…" -- sleep 1
              # Attached: detaching (Ctrl-o d) returns here and the menu exits -> SSH closes.
              # --new-session-with-layout always creates a fresh named session from the layout;
              # plain --layout with --session instead tries to ADD tabs to an (absent) session
              # and dies with "There is no active session!".
              exec zellij --session "$name" --new-session-with-layout "$layout"
            }

            main() {
              banner
              local names choice name
              mapfile -t names < <(list_session_names)

              local -a items=( "  ✦ New session" )
              for n in "''${names[@]}"; do
                items+=( "  $(printf '%-22s' "$n") $(gum style --foreground "$green" "[$(agent_of "$n")]")" )
              done

              choice="$(printf '%s\n' "''${items[@]}" | strip_ansi \
                | gum choose --header "Connect to a session" --height 12)"
              choice="$(printf '%s' "''${choice:-}" | sed 's/^ *//')"
              [ -z "$choice" ] && exit 0

              if [ "$choice" = "✦ New session" ]; then
                create_session || { exit 0; }
              else
                name="$(printf '%s' "$choice" | awk '{print $1}')"
                exec zellij attach "$name"
              fi
            }

            main
    '';
  };
in
{
  options.programs.lani.menu = {
    enable = lib.mkEnableOption "the gum/zellij agent session menu on SSH login";

    user = lib.mkOption {
      type = lib.types.str;
      default = "lani";
      description = "Account whose interactive SSH logins are replaced by the menu.";
    };

    agents = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "pi"
          "opencode"
          "claude"
          "shell"
        ]
      );
      default = [
        "pi"
        "opencode"
        "shell"
      ];
      description = ''
        Agents offered when creating a session, in menu order. Names not listed are never
        referenced, which is how `claude` stays out of the closure until asked for.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = agentMenu;
      defaultText = lib.literalMD "the built `agent-menu` shell application";
      description = ''
        The built agent-menu package. Exposed (read-only) so other modules — e.g.
        the web terminal (programs.lani.webTerminal) — can run the exact same launcher.
      '';
    };

    webLauncher = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = webTermLauncher;
      defaultText = lib.literalMD "the built `web-term-launch` wrapper";
      description = ''
        Launcher the web sidebar drives through ttyd URL args:
        `attach <name>` or `create <name> <agent>`. Exposed so programs.lani.webTerminal
        can run it while reusing the same per-agent launchers as the gum menu.
      '';
    };

    systemPrompt = lib.mkOption {
      type = lib.types.lines;
      default = "You are a helpful coding assistant.";
      description = ''
        System prompt handed to the Claude/Pi agents launched from the menu.
        Parametrize the agents declaratively by setting this in the Nix config.
      '';
    };

    replaceSystemPrompt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If true, fully replace the agent's built-in system prompt (--system-prompt).
        If false (default), append to it (--append-system-prompt).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.gum
      pkgs.zellij
      agentMenu
    ];
    environment.variables.ZELLIJ_CONFIG_DIR = "${zellijConfigDir}";

    # Interactive SSH only — not scp, not `machinectl shell`, which stays a plain shell
    # for maintenance. The ZELLIJ guard keeps panes opened inside a session as ordinary
    # shells rather than nesting the menu.
    programs.bash.interactiveShellInit = ''
      if [ -n "''${SSH_TTY:-}" ] && [ -z "''${ZELLIJ:-}" ] && [ -t 1 ]; then
        exec agent-menu
      fi
    '';
    programs.zsh.interactiveShellInit = lib.mkAfter ''
      if [ -n "''${SSH_TTY:-}" ] && [ -z "''${ZELLIJ:-}" ] && [ -t 1 ]; then
        exec agent-menu
      fi
    '';
  };
}
