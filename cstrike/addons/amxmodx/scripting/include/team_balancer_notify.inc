#if defined TEAM_BALANCER_NOTIFY_INC
  #endinput
#endif
#define TEAM_BALANCER_NOTIFY_INC

#pragma reqlib team_balancer_notify
#if !defined AMXMODX_NOAUTOLOAD
  #pragma loadlib team_balancer_notify
#endif

/*
 * Retrieves prefix.
 *
 * @param prefix         Buffer to store prefix in.
 * @param maxlen         Maximum size of buffer.
 *
 * @noreturn
 */
native tb_get_prefix(prefix[], maxlen);