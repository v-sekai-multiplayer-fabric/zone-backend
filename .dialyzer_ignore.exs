[
  # Baseline: pre-existing warnings from the first `mix dialyzer` run
  # (dialyxir just added, no prior Dialyzer history to compare against).
  # None of these are in code touched by that session -- keeping the
  # gate green from here on, not hiding these permanently. Remove an
  # entry once its file is actually fixed rather than leaving it here
  # after the warning stops firing.
  {"lib/uro/accounts.ex", :call_without_opaque},
  {"lib/uro/controllers/fallback.ex", :invalid_contract},
  {"lib/uro/controllers/identity_proof_controller.ex", :invalid_contract},
  {"lib/uro/controllers/identity_proof_controller.ex", :unknown_type},
  {"lib/uro/controllers/loop.ex", :invalid_contract},
  {"lib/uro/helpers/validation.ex", :no_return},
  {"lib/uro/helpers/validation.ex", :call},
  {"lib/uro/loop_core/combat_core.ex", :unknown_type},
  {"lib/uro/loop_core/progression_core.ex", :unknown_type},
  {"lib/uro/planner/explain.ex", :unknown_type},
  {"lib/uro/planner/replan.ex", :guard_fail},
  {"lib/uro/planner/sol_tree.ex", :unknown_type},
  {"lib/uro/planner/temporal.ex", :guard_fail},
  {"lib/uro/plug/authentication.ex", :no_return},
  {"lib/uro/plug/require_admin.ex", :unknown_type},
  {"lib/uro/plug/require_avatar_upload_permission.ex", :unknown_type},
  {"lib/uro/plug/require_map_upload_permission.ex", :unknown_type},
  {"lib/uro/plug/require_prop_upload_permission.ex", :unknown_type},
  {"lib/uro/plug/require_shared_file_upload_permission.ex", :unknown_type},
  {"lib/uro/plug/require_user.ex", :unknown_type},
  {"lib/uro/router.ex", :callback_not_exported},
  {"lib/uro/shared_content.ex", :call_without_opaque},
  {"lib/uro/user_content.ex", :call_without_opaque}
]
