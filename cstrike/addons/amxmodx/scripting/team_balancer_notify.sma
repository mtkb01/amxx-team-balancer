#include <amxmodx>
#include <amxmisc>

#include <team_balancer>
#include <team_balancer_skill>
#include <team_balancer_stocks>
#include <team_balancer_const>

#define PLUGIN  "Team Balancer: Notify"
#define VERSION "0.1"
#define AUTHOR  "prnl0"

#define DICTIONARY "team_balancer.txt"

new g_pcvar_prefix;
new g_pcvar_print_names_to_console;
new g_pcvar_notify_checking;
new g_pcvar_notify_balance_check_results;
new g_pcvar_notify_forced_balancing;
new g_pcvar_notify_transfers;
new g_pcvar_notify_switches;
new g_pcvar_notify_balancing_failed;

new g_prefix[MAX_PREFIX_LENGTH + 1];

public plugin_init()
{
  register_plugin(PLUGIN, VERSION, AUTHOR);
  register_dictionary(DICTIONARY);

  g_pcvar_prefix                        = register_cvar("tb_notify_prefix", "^3[TB]^1 ");
  g_pcvar_print_names_to_console        = register_cvar("tb_notify_print_names_to_console", "0");
  g_pcvar_notify_checking               = register_cvar("tb_notify_checking_balance", "1");
  g_pcvar_notify_balance_check_results  = register_cvar("tb_notify_balance_check_results", "1");
  g_pcvar_notify_forced_balancing       = register_cvar("tb_notify_forced_balancing", "1");
  g_pcvar_notify_transfers              = register_cvar("tb_notify_transfers", "1");
  g_pcvar_notify_switches               = register_cvar("tb_notify_switches", "1");
  g_pcvar_notify_balancing_failed       = register_cvar("tb_notify_balancing_failed", "1");
}

public plugin_cfg()
{
  if (is_plugin_loaded("Team Balancer: Core") == -1) {
    set_fail_state("^"Team Balancer: Core^" must be loaded.");
  }
}

public plugin_natives()
{
  register_library("team_balancer_notify");
  register_native("tb_get_prefix", "native_get_prefix");
}

public __may_never_be_called() {
  client_print_color(0, 0, {0}, {0});
}

/* Natives */

public native_get_prefix(plugin, argc)
{
  enum {
    param_prefix = 1,
    param_maxlen
  };
  new prefix[MAX_PREFIX_LENGTH + 1];
  get_pcvar_string(g_pcvar_prefix, prefix, charsmax(prefix));
  set_string(param_prefix, prefix, get_param(param_maxlen));
}

/* Forwards */

public tb_checking_balance()
{
  if (get_pcvar_bool(g_pcvar_notify_checking)) {
    get_pcvar_string(g_pcvar_prefix, g_prefix, charsmax(g_prefix));
    client_print_color(
      0, print_team_default, "%s%L", g_prefix, LANG_PLAYER, "CHAT_CHECKING_BALANCE"
    );
  }
}

public tb_balance_checked(bool:needs_balancing)
{
  if (!get_pcvar_bool(g_pcvar_notify_balance_check_results)) {
    return;
  }

  get_pcvar_string(g_pcvar_prefix, g_prefix, charsmax(g_prefix));

  if (needs_balancing) {
    client_print_color(
      0, print_team_default,
      "%s%L", g_prefix, LANG_PLAYER, "CHAT_BALANCING_NECESSARY",
      tb_get_stronger_team() == CS_TEAM_CT ? "CT" : "T", tb_get_team_skill_diff()
    );
  } else {
    client_print_color(
      0, print_team_default, "%s%L", g_prefix, LANG_PLAYER, "CHAT_BALANCING_UNNECESSARY"
    );
  }
}

public tb_forced_balancing(pid)
{
  if (!get_pcvar_bool(g_pcvar_notify_forced_balancing)) {
    return;
  }

  new name[MAX_NAME_LENGTH + 1];
  get_user_name(pid, name, charsmax(name));
  get_pcvar_string(g_pcvar_prefix, g_prefix, charsmax(g_prefix));
  client_print_color(
    0, print_team_default, "%s%L", g_prefix, LANG_PLAYER, "CHAT_FORCED_BALANCING", name
  );
}

public tb_players_transferred(Array:pids, CsTeams:dst)
{
  if (!get_pcvar_bool(g_pcvar_notify_transfers)) {
    return;
  }

  get_pcvar_string(g_pcvar_prefix, g_prefix, charsmax(g_prefix));

  if (ArraySize(pids) <= 2) {
    new names[2][MAX_NAME_LENGTH + 1];
    for (new i = 0; i != ArraySize(pids); ++i) {
      get_user_name(ArrayGetCell(pids, i), names[i], charsmax(names[]));
    }
    if (ArraySize(pids) == 1) {
      client_print_color(
        0, print_team_default,
        "%s%L", g_prefix, LANG_PLAYER, "CHAT_PLAYER_TRANSFERRED",
        names[0], dst == CS_TEAM_CT ? "CT" : "T"
      );
    } else {
      ellipsize(names[0], MAX_FMT_NAME_LENGTH);
      ellipsize(names[1], MAX_FMT_NAME_LENGTH);
      client_print_color(
        0, print_team_default,
        "%s%L", g_prefix, LANG_PLAYER, "CHAT_TWO_PLAYERS_TRANSFERRED",
        names[0], names[1], dst == CS_TEAM_CT ? "CT" : "T"
      );
    }
  } else {
    client_print_color(
      0, print_team_default,
      "%s%L %L", g_prefix,
      LANG_PLAYER, "CHAT_N_PLAYERS_TRANSFERRED", ArraySize(pids), dst == CS_TEAM_CT ? "CT" : "T",
      LANG_PLAYER, get_pcvar_bool(g_pcvar_print_names_to_console)
        ? "CHAT_SEE_CONSOLE" : "GENERAL_NONE"
    );

    if (get_pcvar_bool(g_pcvar_print_names_to_console)) {
      new name[MAX_NAME_LENGTH + 1];
      new msg[(MAX_PLAYERS/2 - 1) * (MAX_NAME_LENGTH + 1) + (40 + 1) * 2 + 1];
      formatex(msg, charsmax(msg), "^n----------------------------------------^n");
      for (new i = 0; i != ArraySize(pids); ++i) {
        get_user_name(ArrayGetCell(pids, i), name, charsmax(name));
        formatex(msg, charsmax(msg), "%s%s^n", msg, name);
      }
      formatex(msg, charsmax(msg), "%s----------------------------------------^n^n", msg);
      con_print(0, msg);
    }
  }
}

public tb_players_switched(Array:pids)
{
  if (!get_pcvar_bool(g_pcvar_notify_switches)) {
    return;
  }

  get_pcvar_string(g_pcvar_prefix, g_prefix, charsmax(g_prefix));

  if (ArraySize(pids) == 1) {
    new names[2][MAX_NAME_LENGTH + 1];
    new pair[2];
    ArrayGetArray(pids, 0, pair);
    get_user_name(pair[0], names[0], charsmax(names[]));
    get_user_name(pair[1], names[1], charsmax(names[]));
    ellipsize(names[0], MAX_FMT_NAME_LENGTH);
    ellipsize(names[1], MAX_FMT_NAME_LENGTH);
    client_print_color(
      0, print_team_default, "%s%L", g_prefix, LANG_PLAYER, "CHAT_TWO_PLAYERS_SWITCHED",
      names[0], names[1]
    );
  } else {
    client_print_color(
      0, print_team_default,
      "%s%L %L", g_prefix,
      LANG_PLAYER, "CHAT_N_PLAYERS_SWITCHED", ArraySize(pids)*2,
      LANG_PLAYER, get_pcvar_bool(g_pcvar_print_names_to_console)
        ? "CHAT_SEE_CONSOLE" : "GENERAL_NONE"
    );

    if (get_pcvar_bool(g_pcvar_print_names_to_console)) {
      new name[MAX_NAME_LENGTH + 1];
      new msg[512*3 + 1];
      formatex(msg, charsmax(msg), "^n----------------------------------------^n");
      for (new i = 0; i != ArraySize(pids); ++i) {
        new pair[2];
        ArrayGetArray(pids, i, pair);
        get_user_name(pair[0], name, charsmax(name));
        formatex(msg, charsmax(msg), "%s%s <-> ", msg, name);
        get_user_name(pair[1], name, charsmax(name));
        formatex(msg, charsmax(msg), "%s%s^n", msg, name);
      }
      formatex(msg, charsmax(msg), "%s----------------------------------------^n^n", msg);
      con_print(0, msg);
    }
  }
}

public tb_balancing_failed()
{
  if (get_pcvar_bool(g_pcvar_notify_balancing_failed)) {
    get_pcvar_string(g_pcvar_prefix, g_prefix, charsmax(g_prefix));
    client_print_color(
      0, print_team_default, "%s%L", g_prefix, LANG_PLAYER, "CHAT_BALANCING_FAILED"
    );
  }
}