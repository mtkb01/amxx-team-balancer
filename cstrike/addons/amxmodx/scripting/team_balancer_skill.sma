#include <amxmodx>
#include <amxmisc>

#include <team_balancer>
#include <team_balancer_const>

#define TB_PLUGIN "Team Balancer: Skill"

#define DEBUG
#if defined DEBUG
  #define DEBUG_DIR "addons/amxmodx/logs/others/team_balancer"
  #define LOG(%0) log_to_file(g_log_filepath, %0)
  #define LOG_PLAYERS log_players

  new g_log_filepath[PLATFORM_MAX_PATH + 1];
#else
  #define LOG(%0) //
#endif

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
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

new g_skill_levels[SkillLevels][SkillLevel] =
{
  { "L-",  0.0 },
  { "L",   1.0 },
  { "L+",  2.0 },
  { "M-",  3.0 },
  { "M",   4.0 },
  { "M+",  5.0 },
  { "H-",  6.0 },
  { "H",   7.0 },
  { "H+",  8.0 },
  { "P-",  9.0 },
  { "P",  10.0 },
  { "P+", 11.0 }
};

new Float:g_skill[MAX_PLAYERS + 1];

new g_pcvar_base;
new g_pcvar_recheck_skill_diff_delay;

new g_xid_ts;
new g_xid_cts;
new g_xid_tnum;
new g_xid_ctnum;

new g_fw_skill_diff_changed;

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
new g_player_data[MAX_PLAYERS + 1][PlayerData];
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

public plugin_init()
{
  register_plugin(TB_PLUGIN, TB_VERSION, TB_AUTHOR);

  /* CVars */

  g_pcvar_base                      = register_cvar("tb_skill_base", "51.0");
  g_pcvar_recheck_skill_diff_delay  = register_cvar("tb_skill_recheck_diff_delay", "1.5");

  register_cvar("tb_skill_diff_threshold", "100.0");
  register_cvar("tb_skill_min_desired_diff", "200.0");
  register_cvar("tb_skill_min_diff_global_delta", "50.0");
  register_cvar("tb_skill_min_diff_local_delta", "25.0");

  /* XVars */

  g_xid_ts       = get_xvar_id("g_ts");
  g_xid_cts      = get_xvar_id("g_cts");
  g_xid_tnum     = get_xvar_id("g_tnum");
  g_xid_ctnum    = get_xvar_id("g_ctnum");

  /* Forwards */

  g_fw_skill_diff_changed = CreateMultiForward(
    "tb_skill_diff_changed", ET_IGNORE, FP_FLOAT, FP_FLOAT
  );

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
  /* Events */

  register_event_ex("DeathMsg", "event_deathmsg", RegisterEvent_Global);
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION

#if defined DEBUG
  /* Miscellaneous */

  new filename[20 + 1];
  get_time("tb_%Y_%m_%d.log", filename, charsmax(filename));
  formatex(g_log_filepath, charsmax(g_log_filepath), "%s/%s", DEBUG_DIR, filename);
#endif
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
  register_native("tb_set_skill_levels", "native_set_skill_levels");
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
  enum {
    param_pid   = 1,
    param_level = 2
  };

  /* TODO: check if player is valid; log if not. */

  new Float:skill = g_skill[get_param(param_pid)];

  if (skill < g_skill_levels[0][sl_threshold]) {
    set_string(param_level, "?", 1);
  } else {
    for (new i = 0; i <= SkillLevels; ++i) {
      if (i == SkillLevels || skill < g_skill_levels[i][sl_threshold]) {
        set_string(
          param_level, g_skill_levels[i - 1][sl_title], charsmax(g_skill_levels[][sl_title])
        );
        break;
      }
    }
  }

  return skill;
}

#if defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
public native_set_player_skill(plugin, argc)
{
  enum {
    param_pid   = 1,
    param_skill = 2
  };
  new pid = get_param(param_pid);

  new Float:skill = get_param_f(param_skill);
  g_skill[pid] = get_pcvar_float(g_pcvar_base) + (skill < 0.0 ? 0.0 : skill);

  check_skill_diff_delayed();

#if defined DEBUG
  new name[MAX_NAME_LENGTH + 1];
  get_user_name(pid, name, charsmax(name));
  LOG("[TB:SKILL::native_set_player_skill] Setting skill of ^"%s^" to %.1f.", name, g_skill[pid]);
#endif // DEBUG
}

public native_set_skill_levels(plugin, argc)
{
  enum { param_levels = 1 };

  new Array:levels = Array:get_param(param_levels);
  if (ArraySize(levels) < SkillLevels)
    return;

  for (new i = 0; i != SkillLevels; ++i)
    ArrayGetArray(levels, i, g_skill_levels[i]);
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
  new Float:t_skill = get_team_skill(CS_TEAM_T);
  new Float:ct_skill = get_team_skill(CS_TEAM_CT);
  if (t_skill == ct_skill) {
    /* Handle edge case wherein teams might have identical skill but differ in
     * player count. Leaving it (determining stronger team) up to chance in this
     * case might/will introduce issues in balancing. */
    return get_xvar_num(g_xid_tnum) > get_xvar_num(g_xid_ctnum) ? CS_TEAM_T : CS_TEAM_CT;
  } else {
    return t_skill > ct_skill ? CS_TEAM_T : CS_TEAM_CT;
  }
}

Float:get_team_skill(CsTeams:team)
{
  new Array:players = Array:(team == CS_TEAM_T ? get_xvar_num(g_xid_ts) : get_xvar_num(g_xid_cts));
  new playersnum = team == CS_TEAM_T ? get_xvar_num(g_xid_tnum) : get_xvar_num(g_xid_ctnum);

  new Float:sum = 0.0;
  for (new i = 0; i != playersnum; ++i)
    sum += g_skill[ArrayGetCell(players, i)];

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