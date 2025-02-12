#if defined TEAM_BALANCER_INC
  #endinput
#endif
#define TEAM_BALANCER_INC

#pragma reqlib team_balancer_core
#if !defined AMXMODX_NOAUTOLOAD
  #pragma loadlib team_balancer_core
#endif

/* Defines > Public */

#define TB_VERSION  "0.1.0-beta"
#define TB_AUTHOR   "prnl0"

#define TB_DICTIONARY "team_balancer.txt"

/* Defines > Internal */

/* Delegate players skill computation to external plugin, the result of which is
 * provided to Team Balancer through the `tb_set_player_skill` native.
 *
 * Note: disables player skill components menu. */
#define TB_BHVR_EXTERNAL_SKILL_COMPUTATION

/* Natives */

/*
 * Tries to force a balancing attempt at the end of the current round.
 *
 * @param pid         PID of player (server if 0) who requested the forced balancing.
 *
 * @noreturn
 */
native tb_balance(pid);

/* Forwards */

/*
 * Called during balance necessity checks.
 *
 * @noreturn
 */
forward tb_checking_balance();

/*
 * Called after balance necessity checks were performed.
 *
 * @param needs_balancing         Boolean indicating whether balancing is needed or not.
 *
 * @noreturn
 */
forward tb_balance_checked(bool:needs_balancing);

/*
 * Called when a player forced a balancing attempt at the end of the current round.
 *
 * @param pid         PID of player who forced the balancing attempt.
 *
 * @noreturn
 */
forward tb_forced_balancing(pid);

/*
 * Called after players have been transferred (i.e., teams balanced).
 *
 * @param pids         IDs of players that were transferred.
 * @param dst          Destination team ID.
 *
 * @noreturn
 */
forward tb_players_transferred(Array:pids, CsTeams:dst);

/*
 * Called after players have been switched (i.e., teams balanced).
 *
 * @param pids         2-element arrays of IDs of players that were switched.
 *
 * @noreturn
 */
forward tb_players_switched(Array:pids);

/*
 * Called after a balancing attempt failed.
 *
 * @noreturn
 */
forward tb_balancing_failed();
