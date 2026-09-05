.pragma library

// userModel.lastUser is sourced from SDDM's state.conf and can be empty (e.g.
// an install interrupted before first login ever wrote one). This greeter
// theme has no username field, so a blank result used to submit an empty
// username silently instead of asking who's logging in. Only a
// single-account machine is unambiguous enough to guess; leave multi-user
// machines to populate lastUser normally rather than picking one of several
// accounts.
function resolveCurrentUser(userModel, nameRole) {
  if (userModel.lastUser)
    return userModel.lastUser
  if (userModel.rowCount() === 1)
    return (userModel.data(userModel.index(0, 0), nameRole) || "").toString()
  return ""
}
