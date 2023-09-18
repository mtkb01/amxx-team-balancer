/* TODO:
 *   - consider keeping track of players manually, instead of calling
 *     `get_playersnum_ex` each time;
 *   - add time-based balance checks (i.e., every `n` seconds). */

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <cellarray>
#include <cstrike> // figure out how to avoid this (included for `cs_set_user_team`)

#include <team_balancer>
#include <team_balancer_skill>
#include <team_balancer_stocks>
#include <team_balancer_const>

#define DEBUG

#define TB_PLUGIN "Team Balancer: Core"

#define TB_CONFIG "team_balancer.cfg"

#define XO_TEAM 114

#if defined DEBUG
  #define DEBUG_DIR "addons/amxmodx/logs/others"
  #define LOG(%0) log_to_file(g_log_filepath, %0)
  #define LOG_PLAYERS log_players

  new g_log_filepath[PLATFORM_MAX_PATH + 1];
  new bool:g_balanced = false;
#else
  #define LOG(%0) //
#endif

new g_pcvar_balancing_strategy;
new g_pcvar_skill_threshold;
new g_pcvar_min_desired_skill;
new g_pcvar_min_diff_global_delta;
new g_pcvar_min_diff_local_delta;
new g_pcvar_player_count_threshold;
new g_pcvar_max_transfers_per_team;
new g_pcvar_delay_before_start;
new g_pcvar_balance_check_trigger;
new g_pcvar_rounds_between_balancing;
new g_pcvar_immunity_type;
new g_pcvar_immunity_amount;
new g_pcvar_forced_balancing_interval;

new g_fw_checking_balance;
new g_fw_balance_checked;
new g_fw_forced_balancing;
new g_fw_players_transferred;
new g_fw_players_switched;
new g_fw_balancing_failed;

new bool:g_needs_balance_check;
public g_rounds_since_last_balance_check;

new g_rounds_elapsed[MAX_PLAYERS + 1];
new g_balancings_invoked[MAX_PLAYERS + 1];

public plugin_init()
{
  register_plugin(TB_PLUGIN, TB_VERSION, TB_AUTHOR);

  /* CVars */

  g_pcvar_balancing_strategy        = register_cvar("tb_balancing_strategy", "2");
  g_pcvar_balance_check_trigger     = register_cvar("tb_balance_check_trigger", "3");
  g_pcvar_rounds_between_balancing  = register_cvar("tb_rounds_between_balancing", "2");
  g_pcvar_forced_balancing_interval = register_cvar("tb_forced_balancing_interval", "2");
  g_pcvar_player_count_threshold    = register_cvar("tb_player_count_threshold", "3");
  g_pcvar_max_transfers_per_team    = register_cvar("tb_max_transfers_per_team", "2");
  g_pcvar_immunity_type             = register_cvar("tb_immunity_type", "2");
  g_pcvar_immunity_amount           = register_cvar("tb_immunity_amount", "1");
  g_pcvar_delay_before_start        = register_cvar("tb_delay_before_start", "60.0");

  /* Forwards */

  g_fw_checking_balance     = CreateMultiForward("tb_checking_balance", ET_IGNORE);
  g_fw_balance_checked      = CreateMultiForward("tb_balance_checked", ET_IGNORE, FP_CELL);
  g_fw_forced_balancing     = CreateMultiForward("tb_forced_balancing", ET_IGNORE, FP_CELL);
  g_fw_players_transferred  = CreateMultiForward(
    "tb_players_transferred", ET_IGNORE, FP_CELL, FP_CELL
  );
  g_fw_players_switched     = CreateMultiForward("tb_players_switched", ET_IGNORE, FP_CELL);
  g_fw_balancing_failed     = CreateMultiForward("tb_balancing_failed", ET_IGNORE);

  /* Events */

  register_logevent("logevent_round_end", 2, "1=Round_End");

#if defined DEBUG
  new filename[20 + 1];
  get_time("tb_%Y_%m_%d.log", filename, charsmax(filename));
  formatex(g_log_filepath, charsmax(g_log_filepath), "%s/%s", DEBUG_DIR, filename);

  register_event("HLTV", "event_new_round", "a", "1=0", "2=0");
#endif

  LOG("[TB:CORE::plugin_init] Loaded.");
}

public plugin_cfg()
{
  new configsdir[PLATFORM_MAX_PATH];
  get_configsdir(configsdir, charsmax(configsdir));
  server_cmd("exec %s/%s", configsdir, TB_CONFIG);
  server_cmd("mp_autoteambalance 0");
  server_exec();

  g_pcvar_skill_threshold       = get_cvar_pointer("tb_skill_diff_threshold");
  g_pcvar_min_desired_skill     = get_cvar_pointer("tb_skill_min_desired_diff");
  g_pcvar_min_diff_global_delta = get_cvar_pointer("tb_skill_min_diff_global_delta");
  g_pcvar_min_diff_local_delta  = get_cvar_pointer("tb_skill_min_diff_local_delta");
}

public plugin_natives()
{
  register_library("team_balancer_core");
  register_native("tb_balance", "native_balance");
}

public client_putinserver(pid)
{
  if (get_pcvar_num(g_pcvar_balance_check_trigger) == _:bct_player_connect_disconnect) {
    LOG("[TB:CORE::client_putinserver] Player connected: g_needs_balance_check -> true");
    g_needs_balance_check = true;
  }

  /* Remove the players' default immunity. */
  g_rounds_elapsed[pid] = get_pcvar_num(g_pcvar_immunity_amount) + 1;
  g_balancings_invoked[pid] = g_rounds_elapsed[pid];
}

public client_disconnected(pid, bool:drop, message[], maxlen)
{
  new CsTeams:team = CsTeams:get_user_team(pid);
  if (
    (team != CS_TEAM_SPECTATOR && team != CS_TEAM_UNASSIGNED)
    && get_pcvar_num(g_pcvar_balance_check_trigger) == _:bct_player_connect_disconnect
  ) {
    LOG( \
      "[TB:CORE::client_disconnected] Player disconnected (team: %d): g_needs_balance_check -> \
      true", team \
    );
    g_needs_balance_check = true;
  }
}

/* Natives */

/* TODO: think this over more seriously; consider adding a flag to control
 * whether to restart round or not. */
public native_balance(plugin, argc)
{
  enum { param_pid = 1 };

  new pid = get_param(param_pid);

  if (pid == 0) {
    if (needs_balancing()) {
      ExecuteForward(g_fw_balance_checked, _, true);
      if (balance()) {
        server_cmd("sv_restartround 1");
      }
    } else {
      ExecuteForward(g_fw_balance_checked, _, false);
    }
    return;
  }

  if (g_needs_balance_check) {
    chat_print(pid, "%L", pid, "CHAT_BALANCING_ALREADY_SCHEDULED");
    return;
  }

  new balancing_interval = get_pcvar_num(g_pcvar_forced_balancing_interval);
  if (g_rounds_since_last_balance_check < balancing_interval) {
    chat_print(
      pid, "%L", pid, "CHAT_BALANCING_NOT_ENOUGH_ROUNDS_ELAPSED",
      balancing_interval, balancing_interval - g_rounds_since_last_balance_check
    );
    return;
  }

  if (!can_check_balance()) {
    chat_print(pid, "%L", pid, "CHAT_BALANCING_CONDITIONS_NOT_MET");
    return;
  }

  LOG("[TB:CORE::native_balance] %d forced a balancing at round end.", pid);

  ExecuteForward(g_fw_forced_balancing, _, pid);
  g_needs_balance_check = true;
}

/* Forwards */

public tb_skill_diff_changed()
{
  if (get_pcvar_num(g_pcvar_balance_check_trigger) == _:bct_skill_diff_changed) {
    LOG("[TB:CORE::tb_skill_diff_changed] Skill diff. changed: g_needs_balance_check -> true");
    g_needs_balance_check = true;
  }
}

/* Hooks */

public logevent_round_end()
{
  ++g_rounds_since_last_balance_check;

  if (!can_check_balance()) {
    return;
  }

  /* `g_needs_balance_check` takes precedence over rounds elapsed since last
   * balance check. It is set under appropriate conditions when balance check
   * trigger is either `bct_player_connect_disconnect` or
   * `bct_skill_diff_changed`, or when a player requests a forced balancing. */
  if (!g_needs_balance_check && get_pcvar_num(g_pcvar_balance_check_trigger) == _:bct_round) {
    if (g_rounds_since_last_balance_check < get_pcvar_num(g_pcvar_rounds_between_balancing)) {
      LOG( \
        "[TB:CORE::logevent_round_end] %d more round/-s until balancing check.", \
        get_pcvar_num(g_pcvar_rounds_between_balancing) - g_rounds_since_last_balance_check \
      );
      return;
    }
  } else if (!g_needs_balance_check) {
    return;
  }

  if (needs_balancing()) {
    ExecuteForward(g_fw_balance_checked, _, true);
    balance();
  } else {
    ExecuteForward(g_fw_balance_checked, _, false);
  }

  increase_immunity_amt(.for_round_based_immunity = true);

  g_rounds_since_last_balance_check = 0;
  g_needs_balance_check = false;
}

#if defined DEBUG
public event_new_round()
{
  if (g_balanced) {
    g_balanced = false;
    LOG_PLAYERS(false);
  }
}
#endif

/* Main logic */

bool:can_check_balance()
{
  if (get_gametime() < get_pcvar_float(g_pcvar_delay_before_start)) {
    LOG( \
      "[TB:CORE::logevent_round_end] Round ended before tb_delay_before_start (%.1f s) elapsed \
      (%.1f s left). Leaving.", \
      get_pcvar_float(g_pcvar_delay_before_start), \
      get_pcvar_float(g_pcvar_delay_before_start) - get_gametime() \
    );
    return false;
  }

  if (
    get_playersnum_ex(GetPlayers_MatchTeam, "CT") <= 1
    && get_playersnum_ex(GetPlayers_MatchTeam, "TERRORIST") <= 1
  ) {
    LOG( \
      "[TB:CORE::logevent_round_end] CTs and Ts have 1 or less players each. Won't balance. \
      Leaving." \
    );
    return false;
  }

  return true;
}

bool:needs_balancing(bool:suppress_fw = false)
{
  if (!suppress_fw) {
    ExecuteForward(g_fw_checking_balance);
  }

  /* Balance if skill difference exceeds some threshold, or ... */
  if (tb_get_team_skill_diff() >= get_pcvar_float(g_pcvar_skill_threshold)) {
    LOG( \
      "[TB:CORE::needs_balancing] Balancing: necessary (skill diff. [%.1f] exceeds threshold \
      [%.1f]).", tb_get_team_skill_diff(), get_pcvar_float(g_pcvar_skill_threshold) \
    );
    return true;
  }

  /* ... teams differ in player numbers by some amount. */
  new player_count_diff = abs(get_playersnum_ex(GetPlayers_MatchTeam, "CT") -
    get_playersnum_ex(GetPlayers_MatchTeam, "TERRORIST"));
  if (player_count_diff > get_pcvar_num(g_pcvar_player_count_threshold)) {
    LOG( \
      "[TB:CORE::needs_balancing] Balancing: necessary (player count diff. [%d] exceeds \
      threshold [%d]).", player_count_diff, get_pcvar_num(g_pcvar_player_count_threshold) \
    );
    return true;
  }

  LOG("[TB:CORE::needs_balancing] Balancing: unnecessary.");

  return false;
}

bool:balance(bool:inform = true)
{
  /* TODO: consider merging the methods somehow. */

  handle_player_count_diff();
  if (!needs_balancing(true)) {
    LOG("[TB:CORE::balance] Player count diff. reduced. Balancing no longer necessary. Leaving.");
    return false;
  }

  new BalancingStrategy:strat = BalancingStrategy:get_pcvar_num(g_pcvar_balancing_strategy);
  static TransferType:balance_chain[BalancingStrategy][TRANSFER_TYPE_NUM] = {
    /* performance */
    {tt_simple_unidir, tt_chain_evaluated_unidir, tt_switch},
    /* balance */
    {tt_chain_evaluated_unidir, tt_simple_unidir, tt_switch},
    /* best diff. */
    {tt_switch, tt_chain_evaluated_unidir, tt_simple_unidir}
  };

  LOG("[TB:CORE::balance] Attempting to balance using %d strategy.", _:strat);
  LOG_PLAYERS(true);

  /* Try all balancing methods. If `diff` satisfies min. desired skill, and the
   * strategy is either performance-oriented or balanced, leave and perform the
   * actual balancing. If it is best diff.-oriented, attempt to find best
   * (lowest) diff.  */
  new Float:final_diff = tb_get_team_skill_diff();
  new Array:final_pids = Invalid_Array;
  new TransferType:final_transfer_type;
  for (new i = 0; i != TRANSFER_TYPE_NUM; ++i) {
    new Float:diff = 0.0;
    new Array:pids = find_transfers(balance_chain[strat][i], diff);
    /* TODO: probably add a CVar to control whether to prioritize this min.
     *       delta requirement over min. desired skill diff. */
    if (diff > final_diff || (final_diff - diff) < get_pcvar_float(g_pcvar_min_diff_global_delta)) {
      LOG( \
        "[TB:CORE::balance] New skill diff. (%.1f) is either greater than the previous skill diff. \
        (%1.f), or the skill diff. delta doesn't satisfy `tb_min_skill_diff_global_delta` (needed: \
        %.1f; found: %.1f). Skipping.", \
        diff, final_diff, get_pcvar_float(g_pcvar_min_diff_global_delta), floatabs(final_diff - diff) \
      );
      ArrayDestroy(pids);
      continue;
    }

    LOG( \
      "[TB:CORE::balance] New best diff: %.1f -> %.1f (abs. delta: %.1f). [Transfer type: %d]", \
      final_diff, diff, final_diff - diff, balance_chain[strat][i] \
    );
    ArrayDestroy(final_pids);
    final_diff = diff;
    final_pids = pids;
    final_transfer_type = balance_chain[strat][i];

    if (diff <= get_pcvar_float(g_pcvar_min_desired_skill) && strat != bs_best_diff) {
      LOG( \
        "[TB:CORE::balance] Skill diff. satisfies `tb_min_desired_skill_diff` (%.1f), and \
        balancing strategy does not seek best diff. Leaving loop.", \
        get_pcvar_float(g_pcvar_min_desired_skill) \
      );
      break;
    }
  }

  if (final_pids == Invalid_Array || ArraySize(final_pids) == 0) {
    LOG("[TB:CORE::balance] Balancing failed.");
    ExecuteForward(g_fw_balancing_failed);
    ArrayDestroy(final_pids);
    return false;
  }

  if (final_transfer_type == tt_switch) {
    switch_players(final_pids, inform);
  } else {
    transfer_players(final_pids, inform);
  }

#if defined DEBUG
  g_balanced = true;
#endif

  ArrayDestroy(final_pids);

  /* FIXME?: might have to make sure player counts do not differ marginally
   * here. Hoping that balancing handles them automatically. */

  increase_immunity_amt(.for_round_based_immunity = false);

  return true;
}

handle_player_count_diff()
{
  /* We only care when weaker team has more players; the other case should be
   * handled through skill balancing. */
  new CsTeams:str_tm = tb_get_stronger_team();
  /* weaker_team_playersnum - stronger_team_playersnum */
  new pc_diff =
    get_playersnum_ex(GetPlayers_MatchTeam, str_tm == CS_TEAM_CT ? "TERRORIST" : "CT") -
    get_playersnum_ex(GetPlayers_MatchTeam, str_tm == CS_TEAM_CT ? "CT" : "TERRORIST");
  if (pc_diff <= get_pcvar_num(g_pcvar_player_count_threshold)) {
    LOG( \
      "[TB:CORE::handle_player_count_diff] Player count diff. (%d) doesn't exceed threshold (%d), \
      or weaker team has fewer players, in which case we cannot use them to reduce player count diff. \
      Leaving.", pc_diff, get_pcvar_num(g_pcvar_player_count_threshold) \
    );
    return;
  }

  new wkr_tm_players[MAX_PLAYERS];
  new wkr_tm_playersnum = 0;
  get_players_ex(
    wkr_tm_players, wkr_tm_playersnum,
    GetPlayers_MatchTeam, str_tm == CS_TEAM_CT ? "TERRORIST" : "CT"
  );

  new Array:weakest_pids = ArrayCreate();
  /* FIXME?: make sure that integer division works the same way as in C++. */
  LOG( \
    "[TB:CORE::handle_player_count_diff] Looking for up to %d weakest players among the weaker \
    team.", (pc_diff + 1)/2 \
  );
  for (new i = 0, end = (pc_diff + 1)/2; i != end; ++i) {
    LOG("[TB:CORE::handle_player_count_diff] Looking for [%d] weakest player.", i + 1);

    new Float:lowest_skill = 99999.0;
    new weakest_pid = -1;
    for (new j = 0; j != wkr_tm_playersnum; ++j) {
      if (ArrayFindValue(weakest_pids, wkr_tm_players[j]) != -1) {
        LOG( \
          "[TB:CORE::handle_player_count_diff] Player (%d) is already present in `weakest_pids`. \
          Skipping.", wkr_tm_players[j] \
        );
        continue;
      }

      new Float:skill = tb_get_player_skill(wkr_tm_players[j]);
      if (skill < lowest_skill) {
        LOG( \
          "[TB:CORE::handle_player_count_diff] New [%d] weakest candidate: %d (%.1f). [Skill: %.1f \
          -> %1.f]", i + 1, wkr_tm_players[j], skill, lowest_skill, skill \
        );
        lowest_skill = skill;
        weakest_pid = wkr_tm_players[j];
      }
    }

    if (weakest_pid == -1) {
      LOG( \
        "[TB:CORE::handle_player_count_diff] No other weakest candidate could be identified. \
        Breaking out of loop." \
      );
      break;
    } else {
      LOG( \
        "[TB:CORE::handle_player_count_diff] Pushing %d weakest player (PID: %d; skill: %.1f) onto \
        `weakest_pids`.", i + 1, weakest_pid, tb_get_player_skill(weakest_pid) \
      );
      ArrayPushCell(weakest_pids, weakest_pid);
    }
  }

  transfer_players(weakest_pids);
  ArrayDestroy(weakest_pids);
}

Array:find_transfers(TransferType:transfer_type, &Float:new_diff)
{
  new CsTeams:str_tm = tb_get_stronger_team();
  new str_tm_players[MAX_PLAYERS];
  new str_tm_playersnum = 0;
  new wkr_tm_players[MAX_PLAYERS];
  new wkr_tm_playersnum = 0;
  get_players_ex(
    str_tm_players, str_tm_playersnum,
    GetPlayers_MatchTeam, str_tm == CS_TEAM_CT ? "CT" : "TERRORIST"
  );
  get_players_ex(
    wkr_tm_players, wkr_tm_playersnum,
    GetPlayers_MatchTeam, str_tm == CS_TEAM_CT ? "TERRORIST" : "CT"
  );

  /* Initially, new diff. is the base diff. */
  new_diff = tb_get_team_skill_diff();

  if (transfer_type == tt_simple_unidir) {
    return find_simple_unidir_transfers(
      new_diff,
      str_tm_players, str_tm_playersnum,
      wkr_tm_playersnum
    );
  } else if (transfer_type == tt_chain_evaluated_unidir) {
    return find_chain_evaluated_unidir_transfers(
      new_diff,
      str_tm_players, str_tm_playersnum,
      wkr_tm_playersnum
    );
  } else {
    return find_switches(
      new_diff,
      str_tm_players, str_tm_playersnum,
      wkr_tm_players, wkr_tm_playersnum
    );
  }
}

Array:find_simple_unidir_transfers(
  &Float:new_diff, str_tm_players[], str_tm_playersnum, wkr_tm_playersnum
) {
  LOG( \
    "[TB:CORE::find_simple_unidir_transfers] Looking for simple unidirectional transfers. [Base \
    skill diff: %.1f; str. team players: %d; wkr. team players: %d]", \
    new_diff, str_tm_playersnum, wkr_tm_playersnum \
  );

  new Array:pids = ArrayCreate();
  new pc_diff = wkr_tm_playersnum - str_tm_playersnum;
  while (
    (pc_diff + 2 <= get_pcvar_num(g_pcvar_player_count_threshold))
    && (ArraySize(pids) < get_pcvar_num(g_pcvar_max_transfers_per_team))
  ) {
    LOG("[TB:CORE::find_simple_unidir_transfers] Looking for [%d] player.", ArraySize(pids) + 1);

    /* Find player that would yield lowest diff. in skill between teams. */
    new best_pid = -1;
    new Float:best_diff = new_diff;
    for (new i = 0; i != str_tm_playersnum; ++i) {
      /* Exclude players that are immune or were already chosen. */
      if (is_player_immune(str_tm_players[i]) || ArrayFindValue(pids, str_tm_players[i]) != -1) {
        LOG( \
          "[TB:CORE::find_simple_unidir_transfers] Player (%d) is either immune or already present \
          in `pids`. Skipping.", str_tm_players[i] \
        );
        continue;
      }

      /* diff = (s_sum - s) - (w_sum + s)
       *      = (s_sum - w_sum) - 2*s
       *      = prev_diff - 2*s */
      new Float:diff = new_diff - 2*tb_get_player_skill(str_tm_players[i]);
      if (floatabs(diff) < floatabs(best_diff)) {
        LOG( \
          "[TB:CORE::find_simple_unidir_transfers] [%d] New best candidate: %d (%.1f). [Skill \
          diff: %.1f -> %.1f (abs. delta: %.1f)]", \
          ArraySize(pids) + 1, \
          str_tm_players[i], tb_get_player_skill(str_tm_players[i]), best_diff, diff, \
          floatabs(best_diff - floatabs(diff)) \
        );
        best_diff = diff;
        best_pid = str_tm_players[i];
        /* TODO: depending on balancing strategy, we should probably check if
         * `best_diff` already satisfies `tb_min_desired_skill_diff` here rather
         * than deferring it to post-loop. */
      }
    }

    /* No (other) suitable player found - leave. */
    if (best_pid == -1) {
      LOG( \
        "[TB:CORE::find_simple_unidir_transfers] No other candidate for transfer could be \
        identified. Leaving loop." \
      );
      break;
    } else {
      /* This only really applies to the best diff.-oriented balancing strategy;
       * see below. */ 
      if (!skill_diff_delta_sufficient(new_diff, best_diff)) {
        LOG( \
          "[TB:CORE::find_simple_unidir_transfers] Best candidate (%d) no longer satisfies skill \
          diff. delta requirement (needed: %.1f; found: %.1f). Leaving loop.", \
          best_pid, get_pcvar_float(g_pcvar_min_diff_local_delta), new_diff - floatabs(best_diff) \
        );
        break;
      }

      LOG( \
        "[TB:CORE::find_simple_unidir_transfers] Pushing %d player (PID: %d; skill: %.1f) onto \
        `pids`. [Skill diff: %.1f -> %.1f (abs. delta: %.1f)]", \
        ArraySize(pids) + 1, best_pid, tb_get_player_skill(best_pid), new_diff, \
        best_diff, floatabs(new_diff - floatabs(best_diff)) \
      );
      new_diff = floatabs(best_diff);
      ArrayPushCell(pids, best_pid);

      /* Leave if:
       *   - `best_diff` is negative (any further transfer would yield a greater
       *      (worse) skill diff.), or ...
       *   - ... `new_diff` satisfies `tb_min_desired_skill_diff`, and balancing
       *     strategy is either performance-oriented or balanced. */
      if (best_diff < 0.0 || skill_diff_sufficient(new_diff)) {
        LOG( \
          "[TB:CORE::find_simple_unidir_transfers] Best diff. is either negative, or skill diff. \
          satisfies `tb_min_desired_skill_diff` and balancing strategy does not seek best diff. \
          Leaving loop." \
        );
        break;
      }

      pc_diff += 2;
    }
  }

  if (ArraySize(pids) >= get_pcvar_num(g_pcvar_max_transfers_per_team)) {
    LOG( \
      "[TB:CORE::find_simple_unidir_transfers] Max. transfers per team (%d) reached.", \
      get_pcvar_num(g_pcvar_max_transfers_per_team) \
    );
  } else if (
    pc_diff == get_pcvar_num(g_pcvar_player_count_threshold)
    || (pc_diff + 2 > get_pcvar_num(g_pcvar_player_count_threshold))
  ) {
    LOG( \
      "[TB:CORE::find_simple_unidir_transfers] Player count diff. threshold (%d) was either \
      reached or would be reached if any more transfers were made. [Player count diff: %d]", \
      get_pcvar_num(g_pcvar_player_count_threshold), pc_diff \
    );
  }
  LOG("[TB:CORE::find_simple_unidir_transfers] Size of `pids`: %d", ArraySize(pids));

  return pids;
}

Array:find_chain_evaluated_unidir_transfers(
  &Float:new_diff, str_tm_players[], str_tm_playersnum, wkr_tm_playersnum
) {
  new seq_str[64 + 1];
  LOG( \
    "[TB:CORE::find_chain_evaluated_unidir_transfers] Base skill diff: %.1f; str. team players: \
    %d; wkr. team players: %d", new_diff, str_tm_playersnum, wkr_tm_playersnum \
  );

  new Float:best_diff = new_diff;
  new Array:best_seq;

  /* FIXME?: make sure that integer division works the same way as in C++. */
  new max_n = 
    (get_pcvar_num(g_pcvar_player_count_threshold) + (str_tm_playersnum - wkr_tm_playersnum))/2;
  new Array:seq = ArrayCreate();
  for (new n = 1; n != max_n + 1; ++n) {
    ArrayClear(seq);
    ArrayResize(seq, n);
    /* Initialize sequence to {0, 1, 2, ..., n - 1}. */
    for (new i = 0; i != n; ++i) {
      ArraySetCell(seq, i, i);
    }
    /* `i == i` circumvents warning when simply using `true`. Could probably
     * omit this altogether. */
    for (new i = 0; i == i; ++i) {
      new Float:skill_sum = 0.0;
      for (new j = 0; j != n; ++j) {
        /* TODO: ensure player is not transferred if he yields little to no
         * change in skill diff. */
        new pid = str_tm_players[ArrayGetCell(seq, j)];
        if (!is_player_immune(pid)) {
          skill_sum += tb_get_player_skill(pid);
        } else {
          LOG( \
            "[TB:CORE::find_chain_evaluated_unidir_transfers] Player (%d) immune. Won't sum. \
            Skipping.", pid \
          );
        }
      }
      new Float:diff = new_diff - 2*skill_sum;
      if (floatabs(diff) < floatabs(best_diff)) {
        seq_str[0] = '^0';
        for (new i = 0; i != n; ++i) {
          formatex(seq_str, charsmax(seq_str), "%s %d", seq_str, ArrayGetCell(seq, i));
        }
        LOG( \
          "[TB:CORE::find_chain_evaluated_unidir_transfers] New best sequence [n = %d]:%s (skill \
          sum: %.1f). [Skill diff: %.1f -> %.1f (abs. delta: %.1f)]", \
          n, seq_str, skill_sum, best_diff, diff, floatabs(floatabs(best_diff) - floatabs(diff)) \
        );
        ArrayDestroy(best_seq);
        best_diff = diff;
        best_seq = ArrayClone(seq);
        /* TODO: depending on balancing strategy, we should probably check if
         * `best_diff` already satisfies `tb_min_desired_skill_diff` here rather
         * than deferring it to post-loop. */
      }

      /* Check whether final sequence was evaluated by comparing it with {
       *   `str_tm_playersnum` - `n`,
       *   `str_tm_playersnum` - (`n` - 1),
       *   ...,
       *   `str_tm_playersnum` - 1
       * }. Break, if so.
       * For example, given `n` = 3, and `str_tm_playersnum` = 15, this looks
       * for the sequence {12, 13, 14}. */
      new bool:end = true;
      for (new j = 0; j != n; ++j) {
        if (ArrayGetCell(seq, j) != str_tm_playersnum - (n - j)) {
          end = false;
          break;
        }
      }
      if (end) {
        break;
      }

      /* Generate next sequence.
       *
       * TODO: elaborate on algo. */
      ArraySetCell(seq, n - 1, ArrayGetCell(seq, n - 1) + 1);
      for (new j = 1; j != n; ++j) {
        if (ArrayGetCell(seq, n - j) == str_tm_playersnum - j + 1) {
          ArraySetCell(seq, n - j - 1, ArrayGetCell(seq, n - j - 1) + 1);
          for (new k = n - j; k != n; ++k) {
            ArraySetCell(seq, k, ArrayGetCell(seq, k - 1) + 1);
          }
        }
      }
    }
  }

  /* TODO: move this into the `for` loop to reflect balancing strategies. */
  if (floatabs(best_diff) < new_diff) {
    LOG( \
      "[TB:CORE::find_chain_evaluated_unidir_transfers] Cloning PID sequence:%s, into `pids`. \
      [Skill diff: %.1f -> %.1f (abs. delta: %.1f)]", \
      seq_str, new_diff, floatabs(best_diff), floatabs(new_diff - floatabs(best_diff)) \
    );
    new_diff = floatabs(best_diff);
    new Array:pids = ArrayCreate();
    for (new i = 0; i != ArraySize(best_seq); ++i) {
      ArrayPushCell(pids, str_tm_players[ArrayGetCell(best_seq, i)]);
    }
    LOG( \
      "[TB:CORE::find_chain_evaluated_unidir_transfers] Size of `pids`: %d", ArraySize(pids) \
    );
    return pids;
  }

  return Invalid_Array;
}

Array:find_switches(
  &Float:new_diff,
  str_tm_players[], str_tm_playersnum,
  wkr_tm_players[], wkr_tm_playersnum
) {
  LOG( \
    "[TB:CORE::find_switches] Looking for switches. [Base skill diff: %.1f; str. team players: %d; \
    wkr. team players: %d]", new_diff, str_tm_playersnum, wkr_tm_playersnum \
  );

  new Array:pids = ArrayCreate(2);
  while (ArraySize(pids) < get_pcvar_num(g_pcvar_max_transfers_per_team)) {
    LOG("[TB:CORE::find_switches] Looking for [%d] pair.", ArraySize(pids) + 1);

    /* TODO: hopefully eventually find a better algorithm because this yields
     *       approx. 512 iterations at 16v16 players assuming a max. of 2
     *       transfers per team. */
    new best_pids[2] = { -1, -1 };
    new Float:best_diff = new_diff;
    for (new i = 0; i != str_tm_playersnum; ++i) {
      /* Exclude players that are immune or were already chosen. */
      if (is_player_immune(str_tm_players[i]) || pid_exists_in_pairs(pids, str_tm_players[i])) {
        LOG( \
          "[TB:CORE::find_switches] Player (%d) is either immune or already present in `pids`. \
          Skipping.", str_tm_players[i] \
        );
        continue;
      }

      for (new j = 0; j != wkr_tm_playersnum; ++j) {
        /* Exclude players that are immune or were already chosen. */
        if (is_player_immune(wkr_tm_players[j]) || pid_exists_in_pairs(pids, wkr_tm_players[j])) {
          LOG( \
            "[TB:CORE::find_switches] Player (%d) is either immune or already present in `pids`. \
            Skipping.", wkr_tm_players[j] \
          );
          continue;
        }

        /* diff = (s_sum - s + w) - (w_sum - w + s)
         *      = (s_sum - w_sum) - 2s + 2w
         *      = prev_diff - 2*(s - w)
         *
         * Ideal case would be (s - w) == prev_diff/2, which would yield a diff.
         * of 0. */
        new Float:diff = new_diff - 2*(
          tb_get_player_skill(str_tm_players[i]) - tb_get_player_skill(wkr_tm_players[j])
        );
        /* TODO: explain logic (appears sound). */
        if (
          (best_diff > 0.0 && floatabs(diff) < best_diff)
          || (best_diff < 0.0 && diff > best_diff && diff < floatabs(best_diff))
        ) {
          LOG( \
            "[TB:CORE::find_switches] [%d] New best candidates: %d (%.1f) and %d (%.1f). [Skill \
            diff: %.1f -> %.1f (abs. delta: %.1f)]", \
            ArraySize(pids) + 1, \
            str_tm_players[i], tb_get_player_skill(str_tm_players[i]), \
            wkr_tm_players[j], tb_get_player_skill(wkr_tm_players[j]), \
            best_diff, diff, floatabs(floatabs(best_diff) - floatabs(diff)) \
          );
          best_diff = diff;
          best_pids[0] = str_tm_players[i];
          best_pids[1] = wkr_tm_players[j];
          /* TODO: depending on balancing strategy, we should probably check if
           * `best_diff` already satisfies `tb_min_desired_skill_diff` here
           * rather than deferring it to post-loop. */
        }
      }
    }

    if (best_pids[0] == -1) {
      LOG( \
        "[TB:CORE::find_switches] No other candidates for switch could be identified. Leaving \
        loop." \
      );
      break;
    } else {
      /* This only really applies to the best diff.-oriented balancing strategy;
       * see `skill_diff_sufficient`. */ 
      if (!skill_diff_delta_sufficient(floatabs(new_diff), floatabs(best_diff))) {
        LOG( \
          "[TB:CORE::find_switches] Best candidates (%d and %d) no longer satisfy skill diff. \
          delta requirement (needed: %.1f; found: %.1f). Leaving loop.", \
          best_pids[0], best_pids[1], get_pcvar_float(g_pcvar_min_diff_local_delta), \
          floatabs(new_diff) - floatabs(best_diff) \
        );
        break;
      }

      LOG( \
        "[TB:CORE::find_switches] Pushing %d pair (PIDs: %d <-> %d; skills: %.1f <-> %.1f) onto \
        `pids`. [Skill diff: %.1f -> %.1f (abs. delta: %.1f)]", \
        ArraySize(pids) + 1, best_pids[0], best_pids[1], \
        tb_get_player_skill(best_pids[0]), tb_get_player_skill(best_pids[1]), new_diff, \
        best_diff, floatabs(new_diff - floatabs(best_diff)) \
      );
      new_diff = best_diff;
      ArrayPushArray(pids, best_pids);

      if (skill_diff_sufficient(new_diff)) {
        LOG( \
          "[TB:CORE::find_switches] Skill diff. satisfies `tb_min_desired_skill_diff`, and \
          balancing strategy does not seek best diff. Leaving loop." \
        );
        break;
      }
    }
  }

  if (ArraySize(pids) >= get_pcvar_num(g_pcvar_max_transfers_per_team)) {
    LOG( \
      "[TB:CORE::find_switches] Max. transfers per team (%d) reached.", \
      get_pcvar_num(g_pcvar_max_transfers_per_team) \
    );
  }
  LOG( \
    "[TB:CORE::find_switches] Size of `pids`: %d; pairs: %d", ArraySize(pids), ArraySize(pids)*2 \
  );

  new_diff = floatabs(new_diff);

  return pids;
}

increase_immunity_amt(bool:for_round_based_immunity)
{
  if (
    ImmunityType:get_pcvar_num(g_pcvar_immunity_type) != it_round_based
    && for_round_based_immunity
  ) {
    return;
  }

  new players[MAX_PLAYERS];
  new playersnum = 0;
  get_players_ex(players, playersnum, GetPlayers_ExcludeHLTV);
  for (new i = 0; i != playersnum; ++i) {
    if (for_round_based_immunity) {
      ++g_rounds_elapsed[players[i]];
      LOG( \
        "[TB:CORE::increase_immunity_amt] Increasing rounds elapsed since they were last balanced \
        for %d: %d -> %d", \
        players[i], g_rounds_elapsed[players[i]] - 1, g_rounds_elapsed[players[i]] \
      );
    } else {
      ++g_balancings_invoked[players[i]];
      LOG( \
        "[TB:CORE::increase_immunity_amt] Increasing balancings invoked since they were last \
        balanced for %d: %d -> %d", \
        players[i], g_balancings_invoked[players[i]] - 1, g_balancings_invoked[players[i]] \
      );
    }
  }
}

transfer_players(&Array:pids, bool:inform = true)
{
  if (pids == Invalid_Array || ArraySize(pids) == 0) {
    LOG("[TB:CORE::transfer_players] Empty or invalid PID array provided. Leaving.");
    return;
  }

  /* We don't make the assumption that the to-be-transferred players belong to
   * the stronger team because a sufficient player count diff. results in a
   * transfer as well. We only assume that all players belong to the same team. */
  new CsTeams:dst =
    CsTeams:get_user_team(ArrayGetCell(pids, 0)) == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT;
  for (new i = 0; i != ArraySize(pids); ++i) {
    new pid = ArrayGetCell(pids, i);
    if (!is_player_immune(pid)) {
      LOG( \
        "[TB:CORE::transfer_players] Transferring %d (%.1f) to %d.", \
        pid, tb_get_player_skill(pid), dst \
      );
      cs_set_user_team(pid, dst, CS_NORESET, false);
      /* Set to -1 here because `increase_immunity_amt` is invoked immediately
       * after balancing, thus resulting in an increment of these
       * state-tracking-params. */
      g_rounds_elapsed[pid] = -1;
      g_balancings_invoked[pid] = -1;
    } else {
      LOG( \
        "[TB:CORE::transfer_players] Player (%d) is immune. Won't transfer. [Rounds elapsed: \
        %d/%d] [Balancings invoked: %d/%d]", \
        pid, \
        g_rounds_elapsed[pid], get_pcvar_num(g_pcvar_immunity_amount), \
        g_balancings_invoked[pid], get_pcvar_num(g_pcvar_immunity_amount) \
      );
    }
  }

  if (inform) {
    ExecuteForward(g_fw_players_transferred, _, pids, dst);
  }
}

switch_players(&Array:pairs, bool:inform = true)
{
  if (pairs == Invalid_Array || ArraySize(pairs) == 0) {
    LOG("[TB:CORE::switch_players] Empty or invalid PID array provided. Leaving.");
    return;
  }

  for (new i = 0; i != ArraySize(pairs); ++i) {
    new pids[2];
    ArrayGetArray(pairs, i, pids);
    LOG( \
      "[TB:CORE::switch_players] Switching %d (%.1f) with %d (%.1f).", \
      pids[0], tb_get_player_skill(pids[0]), pids[1], tb_get_player_skill(pids[1]) \
    );
    new team1 = get_user_team(pids[0]);
    cs_set_user_team(pids[0], CsTeams:get_user_team(pids[1]), CS_NORESET, false);
    cs_set_user_team(pids[1], CsTeams:team1, CS_NORESET, false);
    /* Set to -1 here because `increase_immunity_amt` is invoked immediately
     * after balancing, thus resulting in an increment of these
     * state-tracking-params. */
    g_rounds_elapsed[pids[0]] = -1;
    g_rounds_elapsed[pids[1]] = -1;
    g_balancings_invoked[pids[0]] = -1;
    g_balancings_invoked[pids[1]] = -1;
  }

  if (inform) {
    ExecuteForward(g_fw_players_switched, _, pairs);
  }
}

/* Utilities */

bool:pid_exists_in_pairs(Array:pairs, const pid)
{
  for (new i = 0; i != ArraySize(pairs); ++i) {
    new pair[2];
    ArrayGetArray(pairs, i, pair);
    if (pair[0] == pid || pair[1] == pid) {
      return true;
    }
  }
  return false;
}

bool:skill_diff_delta_sufficient(Float:prev_diff, Float:new_diff)
{
  /* Skill diff. delta is sufficient if it satisfies `tb_min_skill_diff_delta`,
   * or `tb_min_desired_skill_diff` has not yet been reached. */ 
  return (prev_diff - floatabs(new_diff) >= get_pcvar_float(g_pcvar_min_diff_local_delta))
    || (prev_diff > get_pcvar_float(g_pcvar_min_desired_skill));
}

bool:skill_diff_sufficient(Float:diff)
{
  /* Skill diff. is sufficient if it satisfies `tb_min_desired_skill_diff`, and
   * balancing strategy is either performance-oriented or balanced. */
  return get_pcvar_num(g_pcvar_balancing_strategy) != _:bs_best_diff
    && floatabs(diff) <= get_pcvar_float(g_pcvar_min_desired_skill);
}

bool:is_player_immune(const pid)
{
  new ImmunityType:type = ImmunityType:get_pcvar_num(g_pcvar_immunity_type);
  if (type == it_none) {
    return false;
  }
  new amt = get_pcvar_num(g_pcvar_immunity_amount);
  return (type == it_round_based && g_rounds_elapsed[pid] <= amt)
    || (type == it_balance_count_based && g_balancings_invoked[pid] <= amt);
}

#if defined DEBUG
log_team(str[], maxlen, const team[], CsTeams:team_id)
{
  new players[MAX_PLAYERS];
  new playersnum = 0;

  get_players_ex(players, playersnum, GetPlayers_MatchTeam, team);
  formatex(
    str, maxlen,
    "%s^n  %ss (num: %d; skill: %.1f):^n", str, team, playersnum, tb_get_team_skill(team_id)
  );
  new name[MAX_NAME_LENGTH + 1];
  for (new i = 0; i != playersnum; ++i) {
    get_user_name(players[i], name, charsmax(name));
    formatex(
      str, maxlen, "%s    %d. %s: %.1f^n", str, i, name, tb_get_player_skill(players[i])
    );
  }
}

log_players(bool:before_balancing)
{
  new str[1536 + 1];
  formatex(
    str, charsmax(str), "[TB:CORE::log_players] Player list %s balancing:",
    before_balancing ? "before" : "after"
  );

  log_team(str, charsmax(str), "CT", CS_TEAM_CT);
  log_team(str, charsmax(str), "TERRORIST", CS_TEAM_T);

  LOG(str);
}
#endif