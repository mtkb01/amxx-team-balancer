#include <amxmodx>
#include <amxmisc>

#include <team_balancer>

#define TB_PLUGIN "Team Balancer: Skill"

enum (+= 1000)
{
  task_check_skill_diff = 6418
};

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
enum _:PlayerData
{
  bool:pd_connected,
  pd_kills,
  pd_deaths,
  pd_hs
}

new g_player_data[MAX_PLAYERS + 1][PlayerData];
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

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

  g_fw_skill_diff_changed =
    CreateMultiForward("tb_skill_diff_changed", ET_IGNORE, FP_FLOAT, FP_FLOAT);

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
  /* Events */

  register_event_ex("DeathMsg", "event_deathmsg", RegisterEvent_Global);
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION
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
#if defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
  register_native("tb_set_player_skill", "native_set_player_skill");
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION
  register_native("tb_get_team_skill", "native_get_team_skill");
  register_native("tb_get_team_skills", "native_get_team_skills");
  register_native("tb_get_player_skill_diff", "native_get_player_skill_diff");
  register_native("tb_get_team_skill_diff", "native_get_team_skill_diff");
  register_native("tb_get_stronger_team", "native_get_stronger_team");
}

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
public client_putinserver(pid)
{
  g_player_data[pid][pd_connected] = true;
}

public client_disconnected(pid, bool:drop, message[], maxlen)
{
  if (g_player_data[pid][pd_connected]) {
    g_player_data[pid][pd_connected] = false;
    g_player_data[pid][pd_kills] = 0;
    g_player_data[pid][pd_deaths] = 0;
    g_player_data[pid][pd_hs] = 0;

    g_skill[pid] = 0.0;

    check_skill_diff_delayed();
  }
}
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

/* Natives */

public Float:native_get_player_skill(plugin, argc)
{
  enum { param_pid = 1 };
  return g_skill[get_param(param_pid)];
}

#if defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
public native_set_player_skill(plugin, argc)
{
  enum {
    param_pid = 1,
    param_skill = 2
  };
  new Float:skill = get_param_f(param_skill);
  g_skill[get_param(param_pid)] = skill < 0.0 ? 0.0 : skill;
  check_skill_diff_delayed();
}
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

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

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
/* Events */

public event_deathmsg()
{
  enum {
    param_killer_id = 1,
    param_victim_id = 2,
    /* TODO: sort this out somehow; limits plugin to CS only. */
    param_hs = 3
  };

  new kid = read_data(param_killer_id);
  new vid = read_data(param_victim_id);

  ++g_player_data[vid][pd_deaths];
  compute_skill(vid);

  if (kid != vid) {
    ++g_player_data[kid][pd_kills];
    if (read_data(param_hs) == 1) {
      ++g_player_data[kid][pd_hs];
    }
    compute_skill(kid);
  }

  /* TODO: should inform of changed skill, though executing forward here might
   * be stupid. */
}
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

/* Utilities */

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
compute_skill(pid)
{
  if (g_player_data[pid][pd_kills] == 0 || g_player_data[pid][pd_deaths] == 0) {
    g_skill[pid] = 0.0;
    return;
  }
  g_skill[pid] =
    0.6*g_player_data[pid][pd_kills]/g_player_data[pid][pd_deaths]*100 +
    0.4*g_player_data[pid][pd_hs]/g_player_data[pid][pd_kills]*100,
}
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

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

/* Delay is primarily used to avoid spamming forward executions. */
check_skill_diff_delayed()
{
  /* TODO: might replace with a thinker if performance impact is noticeable. */
  remove_task(task_check_skill_diff);
  set_task_ex(
    get_pcvar_float(g_pcvar_recheck_skill_diff_delay), "check_skill_diff", task_check_skill_diff
  );
}

public check_skill_diff()
{
  static Float:skill_diff = 0.0;
  new Float:diff = get_team_skill_diff();
  if (skill_diff != diff) {
    ExecuteForward(g_fw_skill_diff_changed, _, skill_diff, diff);
    skill_diff = diff;
  }
}