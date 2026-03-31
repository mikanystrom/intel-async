/* Copyright (c) 2025 Intel Corporation.  All rights reserved.  See the file COPYRIGHT for more information. */
/* SPDX-License-Identifier: Apache-2.0 */

#include <sys/types.h>
#include <pwd.h>
#ifdef __APPLE__
#include <stdlib.h>
#include <unistd.h>
#else
#include <malloc.h>
#endif
#include <grp.h>

uid_t
UnixGetIds__extract_pwd_uid(struct passwd *pwd)
{
  return pwd->pw_uid;
}

uid_t
UnixGetIds__extract_pwd_gid(struct passwd *pwd)
{
  return pwd->pw_gid;
}

#define PWDBUFSIZ 8192

struct passwd *
UnixGetIds__alloc_getpwnam(const char *name)
{
  char buf[PWDBUFSIZ];
  struct passwd *pwd = (struct passwd *)malloc(sizeof(struct passwd));
  struct passwd *result;
  int error          = getpwnam_r(name, pwd, buf, PWDBUFSIZ, &result);

  if (error || !(result)) {
    free(pwd);
    return NULL;
  } else
    return result;
}

void
UnixGetIds__free_pwd(struct passwd *pwd)
{
  free(pwd);
}

int
UnixGetIds__getgrouplist(const char *user,
                         gid_t group,
                         gid_t *groups,
                         int *ngroups)
{
  return getgrouplist(user, (int)group, (int *)groups, ngroups);
}


