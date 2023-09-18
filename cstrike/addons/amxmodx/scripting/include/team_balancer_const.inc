#if defined TEAM_BALANCER_CONST_INC
  #endinput
#endif
#define TEAM_BALANCER_CONST_INC

/* TB:CORE */

/*
 * Balance check triggers:
 *   - bct_none:
 *       do not trigger balance checks automatically;
 *
 *   - bct_round:
 *       trigger every `tb_rounds_between_balancing` rounds;
 *
 *   - bct_player_connect_disconnect:
 *       trigger at the end of rounds when players had connected or
 *       disconnected;
 *
 *   - bct_skill_diff_changed:
 *       trigger at the end of rounds when skill diff. changed.
 */
enum BalanceCheckTrigger
{
  bct_none = 0,
  bct_round,
  bct_player_connect_disconnect,
  bct_skill_diff_changed
}

/*
 * Balancing strategies:
 *   - bs_performance:
 *       start with lowest cost method; leave when diff. satisfies min.
 *       desired skill diff.;
 *
 *   - bs_balance:
 *       start with medium cost method; leave when diff. satisfies min.
 *       desired skill diff.;
 *
 *   - bs_best_diff:
 *       leave when best diff. is identified. (Ideally,
 *       `transfer_type_simple_unidir` should not even be considered, since
 *       `transfer_type_chain_evaluated_unidir` yields equivalent or better
 *       results.)
 */
enum BalancingStrategy
{
  bs_performance = 0,
  bs_balance,
  bs_best_diff
}

/*
 * Number of transfer types. (See `e_transfer_type`.)
 */
#define TRANSFER_TYPE_NUM 3

/*
 * Transfer/Search types:
 *   - tt_simple_unidir:
 *       iterate over stronger team players, identifying ones that would yield
 *       lowest diff. in skill between the two teams; stop when
 *       either `tb_player_count_threshold` or `tb_max_transfers_per_team` is
 *       reached, subsequent transfers do not yield a sufficient change in skill
 *       diff. (i.e., do not satisfy `tb_min_skill_diff_local_delta`), or
 *       `tb_min_desired_skill_diff` is satisfied and balancing strategy is
 *       either `balancing_strategy_performance` or
 *       `balancing_strategy_balance`.
 *       This method/type is not context-aware, meaning it does not base its'
 *       picks on the skill rating of other players within the team, therefore
 *       it does not always make the best decisions.
 *
 *   - tt_chain_evaluated_unidir:
 *       similar to `tt_simple_unidir`, although now context-aware:
 *       evaluate all possible sequences of transfers (up to length
 *       n = (tb_player_count_threshold + (str_tm_playersnum -
 *       wkr_tm_playersnum))/2) to find the one that would yield the lowest
 *       diff. in skill rating between the two teams.
 *       Performs either equivalently as or better than
 *       `tt_simple_unidir`.
 *
 *   - tt_switch:
 *       find switches that would yield the lowest diff. in skill between the
 *       two teams; stop when `tb_max_transfers_per_team` is reached, subsequent
 *       switches do not yield a sufficient change in skill diff. (i.e., do not
 *       satisfy `tb_min_skill_diff_local_delta`), or
 *       `tb_min_desired_skill_diff` is satisfied and balancing strategy is
 *       either `balancing_strategy_performance` or
 *       `balancing_strategy_balance`.
 *       Usually performs best but is, again, usually most costly.
 */
enum TransferType
{
  tt_simple_unidir = 0,
  tt_chain_evaluated_unidir,
  tt_switch
}

/*
 * Immunity types:
 *   - it_none:
 *       no immunity is applied to transferred players;
 *
 *   - it_round_based:
 *       transferred players are given `tb_immunity_amount` rounds of immunity;
 *
 *   - it_balance_count_based:
 *       transferred players are given `tb_immunity_amount` balance invocations
 *       of immunity.
 */
enum ImmunityType
{
  it_none = 0,
  it_round_based,
  it_balance_count_based
}

/* TB:NOTIFY */

/*
 * Maximum length of prefix specified by `tb_notify_prefix`.
 */
#define MAX_PREFIX_LENGTH 16

/*
 * Maximum length of name when two are to-be-formatted on one chat line.
 */
#define MAX_FMT_NAME_LENGTH 21

#if !defined TB_BHVR_EXTERNAL_SKILL_COMPUTATION
/* TB:SKILL */

/*
 * Skill components.
 */
enum SkillComponent
{
  sc_kills = 1,
  sc_deaths,
  sc_hs
}
#endif // TB_BHVR_EXTERNAL_SKILL_COMPUTATION