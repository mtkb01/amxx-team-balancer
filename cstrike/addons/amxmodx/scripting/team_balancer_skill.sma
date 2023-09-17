#include <amxmodx>
#include <amxmisc>

#include <gunxpmod>
#include <team_balancer>

#define TB_PLUGIN "Team Balancer: Skill"

enum (+= 1000)
{
  task_check_skill_diff = 6418
};

enum _:PlayerData
{
  bool:pd_connected,
  pd_kills,
  pd_deaths,
  pd_hs,
  pd_used_prs,
  pd_bought_prs,
}

new g_player_data[MAX_PLAYERS + 1][PlayerData];
new Float:g_skill[MAX_PLAYERS + 1];

new g_pcvar_recheck_skill_diff_delay;

new g_fw_skill_diff_changed;

public plugin_init()
{
  register_plugin(TB_PLUGIN, TB_VERSION, TB_AUTHOR);

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

public plugin_cfg()
{
  if (is_plugin_loaded("Team Balancer: Core") == -1) {
    set_fail_state("^"Team Balancer: Core^" must be loaded.");
  }
}

public plugin_natives()
{
  register_library("team_balancer_skill");
  register_native("tb_get_player_data", "native_get_player_data");
  register_native("tb_get_player_skill", "native_get_player_skill");
  register_native("tb_get_team_skill", "native_get_team_skill");
  register_native("tb_get_team_skills", "native_get_team_skills");
  register_native("tb_get_player_skill_diff", "native_get_player_skill_diff");
  register_native("tb_get_team_skill_diff", "native_get_team_skill_diff");
  register_native("tb_get_stronger_team", "native_get_stronger_team");
}

public client_putinserver(pid)
{
  g_player_data[pid][pd_connected]  = true;
}

public client_disconnected(pid, bool:drop, message[], maxlen)
{
  if (g_player_data[pid][pd_connected]) {
    g_player_data[pid][pd_connected] = false;
    ExecuteForward(g_fw_skill_diff_changed);
  }
}

/* Natives */

public native_get_player_data(plugin, argc)
{
  enum {
    param_pid = 1,
    param_datum = 2
  };
  return g_player_data[get_param(param_pid)][get_param(param_datum)];
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

/* Hooks/Forwards */

public event_jointeam()
{
  remove_task(task_check_skill_diff);
  set_task_ex(
    get_pcvar_float(g_pcvar_recheck_skill_diff_delay), "check_skill_diff", task_check_skill_diff
  );
}

public gxp_data_loaded(pid, authid[])
{
  if (!is_user_connected(pid)) {
    return;
  }

  g_player_data[pid][pd_kills]      = gxp_get_user_kills(pid);
  g_player_data[pid][pd_deaths]     = gxp_get_user_deaths(pid);
  g_player_data[pid][pd_hs]         = gxp_get_user_hs(pid);
  g_player_data[pid][pd_used_prs]   = get_user_used_prestige(pid);
  g_player_data[pid][pd_bought_prs] = gxp_get_user_bought_prs(pid);

  if (g_player_data[pid][pd_kills] == 0 || g_player_data[pid][pd_deaths] == 0) {
    g_skill[pid] = 0.0;
    return;
  }
  
  g_skill[pid] =
    0.4*(g_player_data[pid][pd_kills]/g_player_data[pid][pd_deaths])*100 +
    0.1*(g_player_data[pid][pd_hs]/g_player_data[pid][pd_kills])*100 +
    0.4*g_player_data[pid][pd_used_prs] +
    0.1*(g_player_data[pid][pd_used_prs] - g_player_data[pid][pd_bought_prs]);
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