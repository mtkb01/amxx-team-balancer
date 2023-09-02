#include <amxmodx>
#include <amxmisc>
#include <cellarray>

#include <team_balancer>
#include <team_balancer_skill>
#include <team_balancer_stocks>

#define PLUGIN  "Team Balancer: Interface"
#define VERSION "0.1"
#define AUTHOR  "prnl0"

#define MAX_TEAM_NAME_LENGTH 4

#define MAX_MENU_SKILLS_ITEMS_PER_PAGE 5

enum e_menu
{
  menu_none,
  menu_skill,
  menu_player_skills,
  menu_player_info
}

enum _:e_player
{
  e_menu:player_menu_id,
  player_menu_page,
  player_menu_filter[MAX_NAME_LENGTH + 1],
  SortMethod:player_menu_sort_method,
  Array:player_menu_pids,
  bool:player_menu_pids_need_update
}

new const g_clcmds[][][32 + 1] = 
{
  {"/skill", "handle_say_skill"}
};

new g_pcvar_delay_before_start;
new g_pcvar_forced_balancing_interval;

new g_pcvar_skill_menu_flag;
new g_pcvar_player_skill_flag;
new g_pcvar_player_info_flag;
new g_pcvar_allow_force_balancing;
new g_pcvar_force_balance_flag;

new g_xid_rounds_since_last_balance_check;

new g_players[MAX_PLAYERS + 1][e_player];
new Array:g_pids;

public plugin_init()
{
  register_plugin(PLUGIN, VERSION, AUTHOR);

  /* CVars */

  g_pcvar_skill_menu_flag       = register_cvar("tb_ui_skill_menu_flag", "");
  g_pcvar_player_skill_flag     = register_cvar("tb_ui_player_skill_flag", "");
  g_pcvar_player_info_flag      = register_cvar("tb_ui_player_info_flag", "l");
  g_pcvar_allow_force_balancing = register_cvar("tb_ui_allow_force_balancing", "1");
  g_pcvar_force_balance_flag    = register_cvar("tb_ui_force_balance_flag", "l");

  /* Client commands */

  register_clcmd("say", "clcmd_say");
  register_clcmd("say_team", "clcmd_say");
  register_clcmd("_name_filter", "clcmd_name_filter");

  /* Menus */

  register_menucmd(register_menuid("Player Skills Menu"), 1023, "handle_player_skills_menu");

  /* Misc. */

  g_pids = ArrayCreate();
}

public plugin_cfg()
{
  if (is_plugin_loaded("Team Balancer: Core") == -1) {
    set_fail_state("^"Team Balancer: Core^" must be loaded.");
  }

  g_pcvar_delay_before_start        = get_cvar_pointer("tb_delay_before_start");
  g_pcvar_forced_balancing_interval = get_cvar_pointer("tb_forced_balancing_interval");

  g_xid_rounds_since_last_balance_check = get_xvar_id("g_rounds_since_last_balance_check");
}

public plugin_end()
{
  for (new i = 0; i != ArraySize(g_pids); ++i) {
    ArrayDestroy(g_players[ArrayGetCell(g_pids, i)][player_menu_pids]);
  }
  ArrayDestroy(g_pids);
}

public client_putinserver(pid)
{
  for (new i = 0; i != ArraySize(g_pids); ++i) {
    g_players[ArrayGetCell(g_pids, i)][player_menu_pids_need_update] = true;
  }

  g_players[pid][player_menu_id] = menu_none;
  g_players[pid][player_menu_page] = 1;
  g_players[pid][player_menu_sort_method] = Sort_Random;

  ArrayPushCell(g_pids, pid);
}

public client_disconnected(pid, bool:drop, message[], maxlen)
{
  for (new i = 0; i != ArraySize(g_pids); ++i) {
    if (ArrayGetCell(g_pids, i) == pid) {
      ArrayDeleteItem(g_pids, i--);
      continue;
    }

    g_players[ArrayGetCell(g_pids, i)][player_menu_pids_need_update] = true;
  }
}

/* Client commands */

public clcmd_say(const pid)
{
  new buffer[64 + 1];
  read_args(buffer, charsmax(buffer));
  remove_quotes(buffer);

  new pos = 0;
  new cmd[32 + 1];
  argparse(buffer, pos, cmd, charsmax(cmd));

  for (new i = 0; i != sizeof(g_clcmds); ++i) {
    if (equali(cmd, g_clcmds[i][0])) {
      callfunc_begin(g_clcmds[i][1]);
      callfunc_push_int(pid);
      /* Pass the rest of the cmd as arguments. */
      replace_stringex(buffer, charsmax(buffer), cmd, "");
      trim(buffer);
      callfunc_push_str(buffer);
      callfunc_end();
      return PLUGIN_HANDLED;
    }
  }

  return PLUGIN_CONTINUE;
}

public clcmd_name_filter(const pid)
{
  if (g_players[pid][player_menu_id] != menu_player_skills) {
    return;
  }

  read_args(g_players[pid][player_menu_filter], charsmax(g_players[][player_menu_filter]));
  remove_quotes(g_players[pid][player_menu_filter]);
  trim(g_players[pid][player_menu_filter]);
  g_players[pid][player_menu_pids_need_update] = true;
  show_player_skills_menu(pid);
}

/* `say`/`say_team` client command handlers */

public handle_say_skill(const pid, const args[])
{
  if (args[0] == '^0') {
    if (!has_pcvar_flags(pid, g_pcvar_skill_menu_flag)) {
      chat_print(pid, "%L", pid, "CHAT_NO_ACCESS");
      return;
    }
    show_skill_menu(pid);
    return;
  }

  new req_pid = find_player_ex(FindPlayer_MatchNameSubstring | FindPlayer_CaseInsensitive, args);
  if (req_pid == 0) {
    chat_print(pid, "%L", pid, "CHAT_PLAYER_NOT_FOUND", args);
  } else if (req_pid == pid) {
    chat_print(pid, "%L", pid, "CHAT_YOUR_SKILL", tb_get_player_skill(pid));
  } else {
    /* We match by substring, so the actual name might not equal the query. */
    new name[MAX_NAME_LENGTH + 1];
    get_user_name(req_pid, name, charsmax(name));
    chat_print(pid, "%L", pid, "CHAT_PLAYER_SKILL", name, tb_get_player_skill(req_pid));
  }
}

/* Menus */

show_skill_menu(const pid)
{
  g_players[pid][player_menu_id] = menu_skill;

  new str[64 + 1];
  formatex(str, charsmax(str), "%L", pid, "MENU_SKILL_TITLE", tb_get_player_skill(pid));
  new menu = menu_create(str, "handle_skill_menu");

  new bool:display_force_balancing_item =
    get_pcvar_bool(g_pcvar_allow_force_balancing)
    && has_pcvar_flags(pid, g_pcvar_force_balance_flag);

  add_fmt_menu_item(menu, true, "%L", pid, "MENU_CT_SKILL", tb_get_team_skill(CS_TEAM_CT));
  add_fmt_menu_item(menu, true, "%L^n", pid, "MENU_T_SKILL", tb_get_team_skill(CS_TEAM_T));
  add_fmt_menu_item(
    menu, !has_pcvar_flags(pid, g_pcvar_player_skill_flag),
    "%L%s", pid, "MENU_PLAYER_SKILLS", display_force_balancing_item ? "^n" : ""
  );

  if (display_force_balancing_item) {
    new Float:time_left = get_pcvar_float(g_pcvar_delay_before_start) - get_gametime();
    new rounds_left =
      get_pcvar_num(g_pcvar_forced_balancing_interval) -
      get_xvar_num(g_xid_rounds_since_last_balance_check);

    if (time_left > 0) {
      add_fmt_menu_item(
        menu, true, "%L %L", pid, "MENU_FORCE_BALANCE", pid, "MENU_TIME_LEFT", time_left
      );
    } else if (rounds_left > 0) {
      add_fmt_menu_item(
        menu, true, "%L %L", pid, "MENU_FORCE_BALANCE", pid, "MENU_ROUNDS_LEFT", rounds_left
      );
    } else {
      add_fmt_menu_item(menu, false, "%L", pid, "MENU_FORCE_BALANCE", pid);
    }
  }

  formatex(str, charsmax(str), "%L", pid, "MENU_EXIT");
  menu_setprop(menu, MPROP_EXITNAME, str);
  menu_setprop(menu, MPROP_EXIT, "MEXIT_ALL");

  menu_display(pid, menu, 0);
}

public handle_skill_menu(pid, menu, item)
{
  enum {
    item_player_skills = 2,
    item_force_balance = 3
  };

  switch (item) {
    case item_player_skills: show_player_skills_menu(pid);
    case item_force_balance: {
      tb_balance(pid);
      show_skill_menu(pid);
    }
    default: g_players[pid][player_menu_id] = menu_none;
  }

  menu_destroy(menu);
  return PLUGIN_HANDLED;
}

show_player_skills_menu(const pid, page = 1)
{
  g_players[pid][player_menu_id] = menu_player_skills;

  new name[MAX_NAME_LENGTH + 1];

  /* Update cache PID list if necessary (i.e., menu shown anew or an update was
   * explicitly requested (e.g., a player joined/disconnected, etc.)). */
  if (
    g_players[pid][player_menu_pids] == Invalid_Array
    || g_players[pid][player_menu_pids_need_update]
  ) {
    ArrayDestroy(g_players[pid][player_menu_pids]);
    /* If no filter was applied, clone the whole PID list. */
    if (g_players[pid][player_menu_filter][0] == '^0') {
      g_players[pid][player_menu_pids] = ArrayClone(g_pids);
    /* Otherwise, filter out players whose names do not match specified filter. */
    } else {
      g_players[pid][player_menu_pids] = ArrayCreate();
      for (new i = 0; i != ArraySize(g_pids); ++i) {
        new item_pid = ArrayGetCell(g_pids, i);
        get_user_name(item_pid, name, charsmax(name));
        if (containi(name, g_players[pid][player_menu_filter]) != -1) {
          ArrayPushCell(g_players[pid][player_menu_pids], item_pid);
        }
      }
    }
    /* Sort updated list if necessary. */
    if (g_players[pid][player_menu_sort_method] != Sort_Random) {
      sort_pid_array(pid);
    }
    g_players[pid][player_menu_pids_need_update] = false;
  }

  new pnum = ArraySize(g_players[pid][player_menu_pids]);
  /* This only applies when filter was provided. Otherwise, it is always
   * non-zero since the calling player is always listed. */
  if (pnum == 0) {
    chat_print(pid, "%L", pid, "CHAT_PLAYER_NOT_FOUND", g_players[pid][player_menu_filter]);
    g_players[pid][player_menu_filter][0] = '^0';
    g_players[pid][player_menu_pids_need_update] = true;
    show_player_skills_menu(pid, page);
    return;
  }

  new end_page = floatround(pnum/float(MAX_MENU_SKILLS_ITEMS_PER_PAGE), floatround_ceil);

  if (page > end_page) {
    page = end_page;
    g_players[pid][player_menu_page] = end_page;
  }

  new body[MAX_MENU_LENGTH + 1];
  new keys = MENU_KEY_0;

  new colors[2][2 + 1];
  colors[0][0] = '\';
  colors[1][0] = '\';
  colors[0][2] = '^0';
  colors[1][2] = '^0';

  /* Format title. */
  if (g_players[pid][player_menu_filter][0] == '^0') {
    formatex(body, charsmax(body), "%L^n^n", pid, "MENU_PLAYER_SKILLS_TITLE", page, end_page);
  } else {
    formatex(
      body, charsmax(body),
      "%L^n^n", pid, "MENU_PLAYER_FILTERED_SKILLS_TITLE",
      page, end_page, floatround(ArraySize(g_pids)/5.0, floatround_ceil),
      g_players[pid][player_menu_filter]
    );
  }

  /* Decide whether items should be disabled or not based on access flag. */
  set_menu_state_by_cond(has_pcvar_flags(pid, g_pcvar_player_info_flag), colors);

  /* Populate with players. */
  new team[MAX_TEAM_NAME_LENGTH + 1];
  new const mipp = MAX_MENU_SKILLS_ITEMS_PER_PAGE;
  for (new i = 1, j = mipp*(page - 1), n = pnum > mipp*page ? mipp*page : pnum; j != n; ++j, ++i) {
    keys |= (1 << (i - 1));

    new item_pid = ArrayGetCell(g_players[pid][player_menu_pids], j);

    team_id_to_name(CsTeams:get_user_team(item_pid), team, charsmax(team));
    get_user_name(item_pid, name, charsmax(name));
    ellipsize(name, 20);

    formatex(
      body, charsmax(body), "%s%s%d. %s%s: \r%.1f %s[\r%s%s] %L^n",
      body, colors[1], i,
      colors[0], name,
      tb_get_player_skill(item_pid),
      colors[0], team, colors[0],
      pid, item_pid == pid ? "MENU_YOU" : "GENERAL_NONE"
    );
  }

  /* Format options for filtering and sorting. */
  set_menu_state_by_cond(
    ArraySize(g_pids) > MAX_MENU_SKILLS_ITEMS_PER_PAGE, colors, keys, MENU_KEY_6
  );
  formatex(
    body, charsmax(body),
    "%s^n%s6. %s%L^n", body, colors[1], colors[0], pid, "MENU_PLAYER_SKILLS_FILTER"
  );
  set_menu_state_by_cond(pnum > 2, colors, keys, MENU_KEY_7);
  formatex(
    body, charsmax(body), "%s%s7. %s%L %L^n^n", body, colors[1], colors[0],
    pid, "MENU_PLAYER_SKILLS_SORT",
    pid, g_players[pid][player_menu_sort_method] == Sort_Ascending
      ? "GENERAL_SORT_DESCENDING" : "GENERAL_SORT_ASCENDING"
  );

  /* Format "Previous"/"Next" items. */
  if (pnum > MAX_MENU_SKILLS_ITEMS_PER_PAGE) {
    if (page == end_page) {
      keys |= MENU_KEY_8;
      formatex(body, charsmax(body), "%s\r8. \w%L^n", body, pid, "MENU_PREV_PAGE");
      formatex(body, charsmax(body), "%s\d9. %L^n^n", body, pid, "MENU_NEXT_PAGE");
    } else if (page == 1) {
      keys |= MENU_KEY_9;
      formatex(body, charsmax(body), "%s\d8. %L^n", body, pid, "MENU_PREV_PAGE");
      formatex(body, charsmax(body), "%s\r9. \w%L^n^n", body, pid, "MENU_NEXT_PAGE");
    } else {
      keys |= MENU_KEY_8 | MENU_KEY_9;
      formatex(body, charsmax(body), "%s\r8. \w%L^n", body, pid, "MENU_PREV_PAGE");
      formatex(body, charsmax(body), "%s\r9. \w%L^n^n", body, pid, "MENU_NEXT_PAGE");
    }
  }

  /* Format exit item. */
  formatex(body, charsmax(body), "%s\r0. \w%L", body, pid, "MENU_RETURN");

  show_menu(pid, keys, body, -1, "Player Skills Menu");
}

public handle_player_skills_menu(pid, item)
{
  enum {
    item_filter = 5,
    item_sort = 6,
    item_prev = 7,
    item_next = 8,
    item_exit = 9
  };

  switch (item) {
    case item_filter: client_cmd(pid, "messagemode _name_filter");
    case item_sort: {
      g_players[pid][player_menu_sort_method] =
        g_players[pid][player_menu_sort_method] == Sort_Ascending
          ? Sort_Descending
          : Sort_Ascending;
      sort_pid_array(pid);
      show_player_skills_menu(pid, g_players[pid][player_menu_page]);
    }
    case item_prev: show_player_skills_menu(pid, --g_players[pid][player_menu_page]);
    case item_next: show_player_skills_menu(pid, ++g_players[pid][player_menu_page]);
    case item_exit: {
      g_players[pid][player_menu_page] = 1;
      g_players[pid][player_menu_sort_method] = Sort_Random;
      ArrayDestroy(g_players[pid][player_menu_pids]);
      show_skill_menu(pid);
    }
    default: {
      show_player_info_menu(
        pid,
        ArrayGetCell(
          g_players[pid][player_menu_pids],
          MAX_MENU_SKILLS_ITEMS_PER_PAGE*(g_players[pid][player_menu_page] - 1) + item
        )
      );
    }
  }

  return PLUGIN_HANDLED;
}

show_player_info_menu(const pid, const pid_info)
{
  g_players[pid][player_menu_id] = menu_player_info;

  new str[64 + 1];

  new name[MAX_NAME_LENGTH + 1];
  get_user_name(pid_info, name, charsmax(name));
  ellipsize(name, 14);

  formatex(str, charsmax(str), "%L", pid, "MENU_PLAYER_INFO_TITLE", name);
  new menu = menu_create(str, "handle_player_info_menu");

  add_fmt_menu_item(menu, true, "%L: \r%d", pid, "MENU_KILLS", tb_get_player_data(pid_info, 1));
  add_fmt_menu_item(menu, true, "%L: \r%d", pid, "MENU_DEATHS", tb_get_player_data(pid_info, 2));
  add_fmt_menu_item(menu, true, "%L: \r%d", pid, "MENU_HS", tb_get_player_data(pid_info, 3));
  add_fmt_menu_item(menu, true, "%L: \r%d", pid, "MENU_PRS", tb_get_player_data(pid_info, 4));
  add_fmt_menu_item(
    menu, true, "%L: \r%d^n", pid, "MENU_BOUGHT_PRS", tb_get_player_data(pid_info, 5)
  );

  formatex(
    str, charsmax(str),
    "%L: \r%.1f + %.1f + %.1f + %.1f \d= \r%.1f",
    pid, "MENU_SKILL",
    0.4*tb_get_player_data(pid_info, 1)/tb_get_player_data(pid_info, 2)*100,
    0.1*tb_get_player_data(pid_info, 3)/tb_get_player_data(pid_info, 1)*100,
    0.4*tb_get_player_data(pid_info, 4),
    0.1*(tb_get_player_data(pid_info, 4) - tb_get_player_data(pid_info, 5)),
    tb_get_player_skill(pid_info)
  );
  add_fmt_menu_item(menu, true, str);

  formatex(str, charsmax(str), "%L", pid, "MENU_RETURN");
  menu_setprop(menu, MPROP_EXITNAME, str);
  menu_setprop(menu, MPROP_EXIT, "MEXIT_ALL");

  menu_display(pid, menu);
}

public handle_player_info_menu(pid, menu, item)
{
  show_player_skills_menu(pid, g_players[pid][player_menu_page]);
  menu_destroy(menu);
  return PLUGIN_HANDLED;
}

/* Utilties */

add_fmt_menu_item(const menu, bool:disabled, const fmt[], any:...)
{
  new str[64 + 1];
  static disable_item_callback = 0;
  if (disable_item_callback == 0) {
    disable_item_callback = menu_makecallback("disable_item");
  }
  vformat(str, charsmax(str), fmt, 4);
  menu_additem(menu, str, .callback = disabled ? disable_item_callback : -1);
}

sort_pid_array(const pid)
{
  new SortMethod:data[1]; data[0] = g_players[pid][player_menu_sort_method];
  ArraySortEx(
    g_players[pid][player_menu_pids],
    "pid_sort_callback",
    _:data
  );
}

team_id_to_name(const CsTeams:tid, name[], const maxlen)
{
  switch (tid) {
    case CS_TEAM_T: formatex(name, maxlen, "T");
    case CS_TEAM_CT: formatex(name, maxlen, "CT");
    case CS_TEAM_SPECTATOR: formatex(name, maxlen, "SPEC");
    case CS_TEAM_UNASSIGNED: formatex(name, maxlen, "?");
  }
}

set_menu_state_by_cond(const bool:cond, colors[2][3], &keys = 0, add_keys = 0)
{
  if (cond) {
    colors[0][1] = 'w';
    colors[1][1] = 'r';
    keys |= add_keys;
  } else {
    colors[0][1] = 'd';
    colors[1][1] = 'd';
  }
}

bool:has_pcvar_flags(const pid, const pcvar)
{
  new pflags[22 + 1];
  get_pcvar_string(pcvar, pflags, charsmax(pflags));
  return pflags[0] == '^0' || (read_flags(pflags) & get_user_flags(pid)) != 0;
}

/* Miscellaneous */

public disable_item(pid, menu, item)
{
  return ITEM_DISABLED;
}

public pid_sort_callback(Array:array, pid1, pid2, const data[], data_size)
{
  new Float:s1 = tb_get_player_skill(pid1);
  new Float:s2 = tb_get_player_skill(pid2);
  if (s1 == s2) {
    return 0;
  } else {
    new SortMethod:sort_method = SortMethod:data[0];
    return (s1 < s2 && sort_method == Sort_Ascending) || (s1 > s2 && sort_method == Sort_Descending)
      ? -1 : 1;
  }
}