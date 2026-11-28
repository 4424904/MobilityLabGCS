# CI results

run 46126127934, commit 9bf576c1272ccbc47c8dfda5a809d3d7438bdbf4

| case | result | checks | metrics |
|---|---|---|---|
| demo | PASS | demo_refused_with_real_vehicle, auto_demo_started, acact_takeover_on_demo, acact_release_on_demo, real_link_blocked_during_demo, real_link_allowed_after_demo, no_sitl_record_from_demo, rec_demo_created, rec_no_real_record_from_demo, rec_track_rows, rec_load_export, agl_on_ground_near_zero | {} |
| gcskill | PASS | killed_during_avoidance, offboard_failsafe, restart_no_takeover, separation, completed | {"min_horizontal_same_layer_m": 8.74, "takeovers": ["D1", "D2"], "killed_at_s": 36.6, "failsafe_after_kill": {"D1": [0.82, "HOLD"], "D2": [0.82, "HOLD"]}} |
| linkloss | PASS | link_cut_during_avoidance, gcs_marked_lost, cut_vehicle_safe, separation, completed | {"min_horizontal_same_layer_m": 6.83, "takeovers": ["D1", "D2"], "d2_failsafe": [1.21, "HOLD"], "cut_at_s": 34.3} |
| modes | PASS | bad_mission_blocked, check_warns_crossing, both_airborne, takeover, separation, returned, completed, modes_switched_in_flight, showcase_refused_with_real_vehicles, never_showcase_with_real_vehicle | {"min_horizontal_same_layer_m": 8.39, "takeovers": ["D1", "D2"]} |
| operator | PASS | operator_hold, not_retaken, resumed, separation, completed | {"min_horizontal_same_layer_m": 9.65, "takeovers": ["D1", "D2"]} |
| preflight | PASS | load_refused_without_site, heading_issue, start_blocked, never_armed | {"min_horizontal_same_layer_m": null, "takeovers": []} |
| s7duo | PASS | mission_loaded, both_airborne, advanced, takeover, separation, returned, completed | {"min_horizontal_same_layer_m": 9.9, "takeovers": ["D1", "D2"]} |
| ardupilot | PASS | speed_in_mission, altitude_in_mission, heading_in_mission, altitude_paused | {} |
| px4 | PASS | speed_in_mission, altitude_in_mission, heading_in_mission, altitude_paused | {} |
| user | PASS | bad_mission_blocked, check_warns_crossing, both_airborne, takeover, separation, returned, completed | {"min_horizontal_same_layer_m": 9.54, "takeovers": ["D1", "D2"]} |
