/// The `r` parameter of the link that opened the app, if any.
String? incomingResultParam() => null;

/// The `x` parameter (a friend's reaction), if any.
String? incomingReactionParam() => null;

/// Removes `?r=...` from the address bar so a reload doesn't re-add it.
void clearIncomingParam() {}
