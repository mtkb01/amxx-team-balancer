#include <amxmodx>
#include <amxmisc>

#define PLUGIN  "Team Balancer: Skill"
#define VERSION "0.1"
#define AUTHOR  "prnl0"

enum (+= 1000)
{
  task_compute_skill = 2749,
  task_check_skill_diff = 6418
};

enum _:e_player
{
  bool:player_connected,
  /* TODO: remove once natives to query player info. become available. */
  player_kills,
  player_deaths,
  player_hs,
  player_used_prs,
  player_bought_prs,
}

new g_players[MAX_PLAYERS + 1][e_player];
new Float:g_skill[MAX_PLAYERS + 1];

new g_pcvar_recheck_skill_diff_delay;

new g_fw_skill_diff_changed;

public plugin_init()
{
  register_plugin(PLUGIN, VERSION, AUTHOR);

  /* CVars */

  g_pcvar_recheck_skill_diff_delay = register_cvar("tb_skill_recheck_diff_delay", "1.5");

  register_cvar("tb_skill_diff_threshold", "100.0");
  register_cvar("tb_skill_min_desired_diff", "200.0");
  register_cvar("tb_skill_min_diff_global_delta", "60.0");
  register_cvar("tb_skill_min_diff_local_delta", "30.0");

  /* Forwards */

  g_fw_skill_diff_changed = CreateMultiForward("tb_skill_diff_changed", ET_IGNORE);

  /* Events */

  register_logevent("event_jointeam", 3, "1=joined team");
}

public plugin_end()
{
  log_to_file("addons/amxmodx/logs/others/tb_2023_08_08.log", "ENDINGADNAJDHKJLAHKJAHDKJAHDKJAHD");
}

public plugin_cfg()
{
  if (is_plugin_loaded("Team Balancer: Core") == -1) {
    set_fail_state("^"Team Balancer: Core^" must be loaded.");
  }
}

public plugin_natives()
{
  register_library("team_balancer_skill");
  register_native("tb_get_player_skill", "native_get_player_skill");
  register_native("tb_get_team_skill", "native_get_team_skill");
  register_native("tb_get_team_skills", "native_get_team_skills");
  register_native("tb_get_player_skill_diff", "native_get_player_skill_diff");
  register_native("tb_get_team_skill_diff", "native_get_team_skill_diff");
  register_native("tb_get_stronger_team", "native_get_stronger_team");

  /* TODO: remove once natives to query player info. become available. */
  register_native("tb_get_player_data", "native_get_player_data");
}

public client_putinserver(pid)
{
  g_players[pid][player_connected]  = true;

  /* TODO: remove once natives to query player info. become available. */
  g_players[pid][player_kills]      = random_num(100, 6000);
  g_players[pid][player_deaths]     = random_num(100, 4000);
  g_players[pid][player_hs]         = random_num(50, g_players[pid][player_kills]);
  g_players[pid][player_used_prs]   = random_num(1, 200);
  g_players[pid][player_bought_prs] = random_num(1, g_players[pid][player_used_prs]);

  set_task_ex(0.5, "compute_skill", task_compute_skill + pid);
}

public client_disconnected(pid, bool:drop, message[], maxlen)
{
  if (g_players[pid][player_connected]) {
    g_players[pid][player_connected] = false;
    ExecuteForward(g_fw_skill_diff_changed);
  }
}

/* Natives */

/* TODO: remove once natives to query player info. become available. */
public native_get_player_data(plugin, argc)
{
  return g_players[get_param(1)][get_param(2)];
}

public Float:native_get_player_skill(plugin, argc)
{
  enum { param_pid = 1 };
  return g_skill[get_param(param_pid)];
}

public Float:native_get_team_skill(plugin, argc)
{
  enum { param_team = 1 };
  return get_team_skill(CsTeams:get_param(param_team));
}

public native_get_team_skills(plugin, argc)
{
  enum {
    param_stronger_team_skill = 1,
    param_weaker_team_skill
  };
  if (get_stronger_team() == CS_TEAM_CT) {
    set_float_byref(param_stronger_team_skill, get_team_skill(CS_TEAM_CT));
    set_float_byref(param_weaker_team_skill, get_team_skill(CS_TEAM_T));
  } else {
    set_float_byref(param_stronger_team_skill, get_team_skill(CS_TEAM_T));
    set_float_byref(param_weaker_team_skill, get_team_skill(CS_TEAM_CT));
  }
}

public Float:native_get_player_skill_diff(plugin, argc)
{
  enum {
    param_pid_lhs = 1,
    param_pid_rhs
  };
  return floatabs(g_skill[get_param(param_pid_lhs)] - g_skill[get_param(param_pid_rhs)]);
}

public Float:native_get_team_skill_diff(plugin, argc)
{
  return get_team_skill_diff();
}

public CsTeams:native_get_stronger_team(plugin, argc)
{
  return get_stronger_team();
}

/* Hooks */

public event_jointeam()
{
  remove_task(task_check_skill_diff);
  set_task_ex(
    get_pcvar_float(g_pcvar_recheck_skill_diff_delay), "check_skill_diff", task_check_skill_diff
  );
}

/* General */

public compute_skill(tid)
{
  new pid = tid - task_compute_skill;
  if (!is_user_connected(pid)) {
    return;
  }
  
  /* TODO: change once natives to query player info. become available. */
  g_skill[pid] =
    0.4*(g_players[pid][player_kills]/g_players[pid][player_deaths])*100 +
    0.1*(g_players[pid][player_hs]/g_players[pid][player_kills])*100 +
    0.4*g_players[pid][player_used_prs] +
    0.1*(g_players[pid][player_used_prs] - g_players[pid][player_bought_prs]);
}

/* Utilities */

CsTeams:get_stronger_team()
{
  return get_team_skill(CS_TEAM_CT) > get_team_skill(CS_TEAM_T) ? CS_TEAM_CT : CS_TEAM_T;
}

Float:get_team_skill(CsTeams:team)
{
  new players[MAX_PLAYERS];
  new playersnum = 0;
  get_players_ex(
    players, playersnum, GetPlayers_MatchTeam, team == CS_TEAM_CT ? "CT" : "TERRORIST"
  );

  new Float:sum = 0.0;
  for (new i = 0; i != playersnum; ++i) {
    sum += g_skill[players[i]];
  }

  return sum;
}

Float:get_team_skill_diff()
{
  return floatabs(get_team_skill(CS_TEAM_CT) - get_team_skill(CS_TEAM_T));
}

/* Miscellaneous */

public check_skill_diff()
{
  static Float:skill_diff = 0.0;
  new Float:diff = get_team_skill_diff();
  if (skill_diff != diff) {
    skill_diff = diff;
    ExecuteForward(g_fw_skill_diff_changed);
  }
}