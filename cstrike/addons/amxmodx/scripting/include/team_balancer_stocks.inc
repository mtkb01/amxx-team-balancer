#if defined TEAM_BALANCER_STOCKS_INC
  #endinput
#endif
#define TEAM_BALANCER_STOCKS_INC

#include <team_balancer_notify>
#include <team_balancer_const>

/* TB:NOTIFY */

/*
 * Prints formatted message to the players' chat/-s.
 *
 * @param pid         Receiving player ID (or 0 for all players).
 * @param fmt         Formatting rules.
 * @param ...         Variable number of formatting parameters.
 *
 * @noreturn
 *
 * NOTE: should only be used when either `pid` != 0, formatting doesn't include
 * multilingual specifier, or language specifier is `LANG_SERVER`. If `pid` is
 * 0, formatting is multilingual, and the language specifier is `LANG_PLAYER`,
 * this will yield unpredictable results (e.g., text in random languages not
 * chosen by the end-user).
 *
 * TODO: eventually, the above should somehow be fixed.
 */
stock chat_print(const pid, const fmt[], any:...)
{
  new msg[MAX_FMT_LENGTH + 1];
  new prefix[MAX_PREFIX_LENGTH + 1];
  vformat(msg, charsmax(msg), fmt, 3);
  tb_get_prefix(prefix, charsmax(prefix));
  client_print_color(pid, print_team_default, "%s%s", prefix, msg);
}

/*
 * Prints formatted message to players' console/-s.
 *
 * @param pid         Receiving player ID (or 0 for all players).
 * @param fmt         Formatting rules.
 * @param ...         Variable number of formatting parameters.
 *
 * @noreturn
 */
stock con_print(const pid, const fmt[], any:...)
{
  static msg[1024 + 1];
  vformat(msg, charsmax(msg), fmt, 3);

  if (pid != 0) {
    console_print(pid, msg);
    return;
  }

  new players[MAX_PLAYERS];
  new playersnum = 0;
  get_players_ex(players, playersnum, GetPlayers_ExcludeBots);
  for (new i = 0; i != playersnum; ++i) {
    console_print(players[i], msg);
  }
}

/*
 * Ellipsizes string (replaces chars with ellipsis (...)) if it is longer than
 * specified max. length.
 *
 * @param str         String to be ellipsized.
 * @param maxlen      Max. length `str` can be before it is ellipsized.
 *
 * @noreturn
 */
stock ellipsize(str[], maxlen)
{
  if (strlen(str) <= maxlen || maxlen < (1 + 3 + 3)) {
    return;
  }

  copy(str, maxlen, str);
  str[maxlen - 6] = '.';
  str[maxlen - 5] = '.';
  str[maxlen - 4] = '.';
}