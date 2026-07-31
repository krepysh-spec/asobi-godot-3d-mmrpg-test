-- Server manifest.
--
-- Two separate things live in this file:
--   * globals    -> server settings (guest_auth and friends)
--   * the return -> the mode manifest, a plain {mode_name = "script.lua"} map.
--     Every value there must be a script path string, so settings cannot be
--     nested inside it.
--
-- guest_auth only takes effect here; setting it in world.lua is silently
-- ignored. It also needs ASOBI_GUEST_VERIFIER_PEPPER (>= 32 bytes) in the
-- environment, or guest sign-in fails closed with guest_auth_disabled.
guest_auth = true

return {
    spawns = "world.lua",
}
