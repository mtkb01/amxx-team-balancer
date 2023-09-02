# Team Balancer

An [AMX Mod X](https://www.amxmodx.org/) plugin for [Counter-Strike 1.6](https://store.steampowered.com/app/10/CounterStrike/) that performs static team balancing (i.e., based on a skill rating precomputed upon connection to the server, rather than on frags/deaths accumulated throughout the game). See [§ Operation](#operation) for details.

## Requirements

- HLDS
- Metamod
- AMX Mod X (>= 1.9.0)

## Installation

1. Download the [latest release](https://github.com/prnl0/amxx-team-balancer/releases/latest).
2. Extract the 7z archive into your HLDS folder.
3. Append `team_balancer_core.amxx` and `team_balancer_skill.amxx` to `configs/plugins.ini`.
4. _(Optional)_ Append `team_balancer_info.amxx` and `team_balancer_ui.amxx` to the same file if you need/want the features these sub-plugins offer.

## Configuration (CVars)

<details>
<summary>CVars (click to expand) </summary>

_Note: the min. and max. values are not currently enforced, and are only provided as sensible bounds._

<table>
  <tr>
    <td>CVar</td>
    <td align="center">Type</td>
    <td align="center">Def. value</td>
    <td align="center">Min. value</td>
    <td align="center">Max. value</td>
    <td>Description</td>
  </tr>
  <tr><td colspan="6" align="center">General</td></tr>
  <tr>
    <td><code>tb_balancing_strategy</code></td>
    <td align="center">integer</td>
    <td align="center">2</td>
    <td align="center">0</td>
    <td align="center">2</td>
    <td>
      Balancing strategy to use.<br>
      <code>0</code> - performance;<br>
      <code>1</code> - balanced;<br>
      <code>2</code> - best diff.<br>
      For details, see <a href="#balancing-strategies">§ Balancing strategies</a>.
    </td>
  </tr>
  <tr>
    <td><code>tb_player_count_threshold</code></td>
    <td align="center">integer</td>
    <td align="center">3</td>
    <td align="center">1</td>
    <td align="center">31</td>
    <td>Maximum tolerable difference in player count between the two teams.</td>
  </tr>
  <tr>
    <td><code>tb_max_transfers_per_team</code></td>
    <td align="center">integer</td>
    <td align="center">2</td>
    <td align="center">1</td>
    <td align="center">16</td>
    <td>Maximum amount of players that can be transferred from a team.</td>
  </tr>
  <tr>
    <td><code>tb_delay_before_start</code></td>
    <td align="center">float</td>
    <td align="center">60.0</td>
    <td align="center">0.0</td>
    <td align="center">-</td>
    <td>Amount of time (in seconds) to wait before engaging automatic balancing.</td>
  </tr>
  <tr>
    <td><code>tb_balance_check_trigger</code></td>
    <td align="center">integer</td>
    <td align="center">3</td>
    <td align="center">0</td>
    <td align="center">3</td>
    <td>
      Balance check trigger to use.<br>
      <code>0</code> - none;<br>
      <code>1</code> - round;<br>
      <code>2</code> - player connect/disconnect;<br>
      <code>3</code> - skill diff. change.<br>
      For details, see <a href="#triggers">§ Triggers</a>.
    </td>
  </tr>
  <tr>
    <td><code>tb_rounds_between_balancing</code></td>
    <td align="center">integer</td>
    <td align="center">2</td>
    <td align="center">0</td>
    <td align="center">-</td>
    <td>Number of rounds in-between any type of balancings.</td>
  </tr>
  <tr>
    <td><code>tb_immunity_type</code></td>
    <td align="center">integer</td>
    <td align="center">2</td>
    <td align="center">0</td>
    <td align="center">2</td>
    <td>
      Type of immunity to grant transferred players.<br>
      <code>0</code> - none;<br>
      <code>1</code> - round-based (immune for <code>tb_immunity_amount</code> rounds);<br>
      <code>2</code> - balance count-based (immune for <code>tb_immunity_amount</code> number of balancings).
    </td>
  </tr>
  <tr>
    <td><code>tb_immunity_amount</code></td>
    <td align="center">integer</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">-</td>
    <td>Amount of immunity to grant transferred players. Corresponds to rounds if <code>tb_immunity_type</code> is <code>1</code>, or number of balancings if it is <code>2</code>; irrelevant otherwise.</td>
  </tr>
  <tr>
    <td><code>tb_forced_balancing_interval</code></td>
    <td align="center">integer</td>
    <td align="center">2</td>
    <td align="center">0</td>
    <td align="center">-</td>
    <td>Number of rounds in-between any type of balancing and a forced one.</td>
  </tr>
  <tr><td colspan="6" align="center">Skill</td></tr>
  <tr>
    <td><code>tb_skill_diff_threshold</code></td>
    <td align="center">float</td>
    <td align="center">100.0</td>
    <td align="center">10.0</td>
    <td align="center">-</td>
    <td>Skill difference threshold at which teams are considered to be in a disbalance, and balancing is required.</td>
  </tr>
  <tr>
    <td><code>tb_skill_min_desired_diff</code></td>
    <td align="center">float</td>
    <td align="center">200.0</td>
    <td align="center">15.0</td>
    <td align="center">-</td>
    <td>Skill difference threshold at which teams are considered to have been balanced. Relevant only if <code>tb_balancing_strategy</code> is <code>0</code> or <code>1</code>.</td>
  </tr>
  <tr>
    <td><code>tb_skill_min_diff_global_delta</code></td>
    <td align="center">float</td>
    <td align="center">60.0</td>
    <td align="center">5.0</td>
    <td align="center">-</td>
    <td>Minimum required change in skill diff. from current diff. to consider the identified candidates for transfer.</td>
  </tr>
  <tr>
    <td><code>tb_skill_min_diff_local_delta</code></td>
    <td align="center">float</td>
    <td align="center">30.0</td>
    <td align="center">1.0</td>
    <td align="center">-</td>
    <td>Minimum required change in skill diff. from previously identified best diff. to consider player a viable candidate for transfer.</td>
  </tr>
  <tr>
    <td><code>tb_skill_recheck_diff_delay</code></td>
    <td align="center">float</td>
    <td align="center">1.5</td>
    <td align="center">0.0</td>
    <td align="center">-</td>
    <td>Amount of time (in seconds) to wait after the last team join event occurs before rechecking skill difference between teams.</td>
  </tr>
  <tr><td colspan="6" align="center">Information</td></tr>
  <tr>
    <td><code>tb_info_prefix</code></td>
    <td align="center">string</td>
    <td align="center"><code>"^3[TB]^1 "</code></td>
    <td align="center">0 (chars)</td>
    <td align="center">16 (chars)</td>
    <td>Prefix printed before every chat message issued by the plugin.</td>
  </tr>
  <tr>
    <td><code>tb_info_print_names_to_console</code></td>
    <td align="center">boolean</td>
    <td align="center">0</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Print the names of transferred players to everyones' consoles.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_info_checking_balance</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Notify players that team balance is currently being checked.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_info_balance_check_results</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Notify players of the result of balance check.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_info_forced_balancing</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Notify players that someone requested a forced balancing.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_info_transfers</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Notify players that someone was transferred to opposing team.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_info_switches</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Notify players that some clients were switched teams.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_info_balancing_failed</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Notify players that a balancing attempt failed.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr><td colspan="6" align="center">Interface</td></tr>
  <tr>
    <td><code>tb_ui_skill_menu_flag</code></td>
    <td align="center">string</td>
    <td align="center"><code>""</code></td>
    <td align="center">-</td>
    <td align="center">-</td>
    <td>Required flag to access <code>/skill</code> menu.</td>
  </tr>
  <tr>
    <td><code>tb_ui_player_skill_flag</code></td>
    <td align="center">string</td>
    <td align="center"><code>"l"</code></td>
    <td align="center">-</td>
    <td align="center">-</td>
    <td>Required flag to access list of players' skill ratings.</td>
  </tr>
  <tr>
    <td><code>tb_ui_player_info_flag</code></td>
    <td align="center">string</td>
    <td align="center"><code>"l"</code></td>
    <td align="center">-</td>
    <td align="center">-</td>
    <td>Required flag to access individual players' skill rating components.</td>
  </tr>
  <tr>
    <td><code>tb_ui_allow_force_balancing</code></td>
    <td align="center">boolean</td>
    <td align="center">1</td>
    <td align="center">0</td>
    <td align="center">1</td>
    <td>
      Allow players with appropriate access to force a balancing attempt at the end of the current round.<br>
      <code>0</code> - disabled;<br>
      <code>1</code> - enabled.
    </td>
  </tr>
  <tr>
    <td><code>tb_ui_force_balance_flag</code></td>
    <td align="center">string</td>
    <td align="center"><code>"l"</code></td>
    <td align="center">-</td>
    <td align="center">-</td>
    <td>Required flag to access forced balancing.</td>
  </tr>
</table>
</details>

## Modules

- FakeMeta

## Operation

When a map is loaded, we wait `tb_delay_before_start` seconds before doing anything. After this delay has elapsed, we check, at the end of each round, whether certain triggers (see [§ Triggers](#triggers)) were activated (or should be activated, in the case of regular (round-based) triggers). If they have, and if the difference in skill or player count between the two teams is significant (this being defined by `tb_skill_diff_threshold` and `tb_player_count_threshold`, respectively), and both teams have at least 2 players, we attempt to balance them using either one of three balancing strategies (see [§ Balancing strategies](#balancing-strategies)). _(Note: this, and the delay can be overriden by a forced balancing that has higher precedence and can be invoked by either the server or a player with appropriate access.)_ To do this, we evaluate the result transferring a certain player would yield using three different algorithms (see [§ Algorithms](#algorithms)) to identify the best candidates for transfer. If any are found, and result in a sufficient skill diff. delta (`tb_skill_min_diff_global_delta`), we perform the transfers; otherwise, we hold that the balancing has failed, and wait for the triggers to be activated again.

The skill rating itself is computed 0.5 s after a client is `putinserver` (though it should probably be computed immediately, without delay). Currently, the function that performs the actual computation ([`compute_skill`](https://github.com/prnl0/amxx-team-balancer/blob/111167f15633da1c9d0cfa24f4fb76d9e9264dbe/cstrike/addons/amxmodx/scripting/team_balancer_skill.sma#L163-L176)) is hardcoded and uses the following formula:
$$0.4k\cdot\frac{\text{kills}}{\text{deaths}} + 0.1k\cdot\frac{\text{headshots}}{\text{kills}} + 0.4\text{prs}\_\text{used} + 0.1\cdot(\text{prs}\_\text{used} - \text{prs}\_\text{bought})\text{,}$$
where $k = 100$ is the scaling factor.

### Triggers

We define three balance check triggers:
- **regular (round-based):** trigger every `tb_rounds_between_balancing` rounds;
- **player connection/disconnection:** trigger when a player connects/disconnects;
- **change in skill diff. between teams:** trigger when the skill difference between the two teams changes (checked `tb_skill_recheck_diff_delay` seconds after the last team join event occurs).

There is also a fourth "trigger" type which completely disables automatic balance checks (`tb_balance_check_trigger 0`).

### Balancing strategies

The three balancing strategies include:
- **performance**: start with lowest cost algorithm (simple unidirectional); assume teams are balanced when skill diff. satisfies both `tb_skill_min_diff_global_delta` and `tb_skill_min_desired_diff` (note: this will probably be reconsidered to prioritize min. desired skill diff. over global delta requirement);
- **balanced**: start with medium cost algorithm (chain-evaluated unidirectional); assume teams are balanced under the same conditions as _performance_ strategy;
- **best difference**: exhaust all algorithms to find the best skill difference that satisfies both `tb_skill_min_diff_global_delta` and `tb_skill_min_desired_diff` (see note in _performance_ strategy description, above).

### Algorithms

The three algorithms for identifying the best candidates for transfer include:
- **simple unidirectional**:  iterate over stronger team players, identifying ones that would yield lowest diff. in skill between the two teams; stop when either `tb_player_count_threshold` or `tb_max_transfers_per_team` is reached, subsequent transfers do not yield a sufficient change in skill diff. (i.e., do not satisfy `tb_skill_min_diff_local_delta`), or `tb_skill_min_desired_diff` is satisfied and balancing strategy is either _performance_ or _balanced_. This algorithm is not context-aware, meaning it does not base its' picks on the skill rating of other players within the team; therefore it does not always make the best decisions.
- **chain-evaluated unidirectional**: similar to _simple unidirectional_, although now context-aware: evaluate all possible sequences/chains of transfers (up to length $n = \($`tb_player_count_threshold` + $(\text{pnum}\_\text{str} - \text{pnum}\_\text{wkr}))/2$) to find the one that would yield the lowest diff. in skill between the two teams. Performs either equivalently as or better than _simple unidirectional_;
- **switch**: find switches that would yield lowest diff. in skill between the two teams; stop when `tb_max_transfers_per_team` is reached, subsequent switches do not yield a sufficient change in skill diff. (i.e., do not satisfy `tb_skill_min_diff_local_delta`), or `tb_skill_min_desired_diff` is satisfied and balancing strategy is either _performance_ or _balanced_. Usually performs best but is typically most costly.
