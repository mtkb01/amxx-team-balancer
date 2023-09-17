#if defined TEAM_BALANCER_SKILL_INC
  #endinput
#endif
#define TEAM_BALANCER_SKILL_INC

#pragma reqlib team_balancer_skill
#if !defined AMXMODX_NOAUTOLOAD
  #pragma loadlib team_balancer_skill
#endif

#include <team_balancer_const>

/*
 * Retrieves a players' individual skill component.
 *
 * @param pid               Player ID to retrieve skill component of.
 * @param component         Skill component to retrieve.
 *
 * @return                  Skill component of player identified by `pid`.
 */
native tb_get_player_skill_comp(const pid, const SkillComponent:component);

/*
 * Retrieves a players' skill rating.
 *
 * @param pid         Player ID to retrieve skill of.
 *
 * @return            Skill of player identified by `pid`.
 */
native Float:tb_get_player_skill(const pid);

/*
 * Retrieves aggregate skill rating of players within a specified team.
 *
 * @param team        Team ID to retrieve aggregate skill rating of.
 *
 * @return            Aggregate skill rating of players within team identified by `team`. 
 */
native Float:tb_get_team_skill(const CsTeams:team);

/*
 * Stores aggregate skill rating of players of both teams.
 *
 * @param stronger_team_skill         Variable to store aggregate skill of stronger team.
 * @param weaker_team_skill           Variable to store aggregate skill of weaker team.
 *
 * @noreturn
 */
native tb_get_team_skills(&Float:stronger_team_skill, &Float:weaker_team_skill);

/*
 * Retrieves difference in skill rating between two players.
 *
 * @param pid_lhs        PID of first player.
 * @param pid_rhs        PID of second player.
 *
 * @return               Difference in skill rating between the two players.
 */
native Float:tb_get_player_skill_diff(const pid_lhs, const pid_rhs);

/*
 * Retrieves difference in skill rating between the two teams.
 *
 * @return               Difference in skill rating between the two teams.
 */
native Float:tb_get_team_skill_diff();

/*
 * Retrieves team with higher aggregate skill rating.
 *
 * @return            Team with higher aggregate skill.
 */
native CsTeams:tb_get_stronger_team();

/*
 * Called when skill difference between teams has changed.
 *
 * @noreturn
 */
forward tb_skill_diff_changed();