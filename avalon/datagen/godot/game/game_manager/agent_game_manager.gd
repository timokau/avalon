extends GameManager

class_name AgentGameManager

var env_bridge: GymEnvBridge
var last_action: PoolByteArray
var is_reply_requested := false
var input_pipe_path: String
var output_pipe_path: String


func _init(_root: Node, _avalon_spec, _input_pipe_path: String, _output_pipe_path: String).(
	_root, _avalon_spec
):
	input_pipe_path = _input_pipe_path
	output_pipe_path = _output_pipe_path

	env_bridge = GymEnvBridge.new(input_pipe_path, output_pipe_path)

	world_node.add_child(load(default_scene_path).instance())


func should_try_to_spawn_player() -> bool:
	# need to apply one action before spawning so that nodes are in a reasonable place
	return (
		.should_try_to_spawn_player()
		and (
			not player.is_human_playback_enabled
			or player.is_human_playback_enabled and frame == 1
		)
	)


func spawn() -> void:
	if player.is_human_playback_enabled:
		player.configure_nodes_for_playback(
			input_collector.arvr_camera_transform,
			input_collector.arvr_left_hand_transform,
			input_collector.arvr_right_hand_transform,
			input_collector.arvr_origin_transform,
			input_collector.human_height if input_collector.human_height != 0.0 else 2.0,
			true
		)
		# reset frame counter
		frame = 0

	.spawn()


func read_input_from_pipe() -> bool:
	if env_bridge.is_output_enabled and is_reply_requested:
		var interactive_observation = observation_handler.get_interactive_observation(
			player, episode, frame, selected_features, true, true
		)
		env_bridge.write_step_result_to_pipe(interactive_observation)

	log_debug_info()

	# process messages until we encounter one that requires a tick:
	while true:
		var decoded_message = env_bridge.read_message()
		match decoded_message:
			[CONST.RESET_MESSAGE, var data, var episode_seed, var world_path, var starting_hit_points]:
				last_action = data
				episode = episode_seed
				player.hit_points = starting_hit_points
				advance_episode(world_path)
				is_reply_requested = true
				# must reset the `input_collector` before we can take the next action
				input_collector.reset()
				return false
			[CONST.RENDER_MESSAGE]:
				env_bridge.render_to_pipe(observation_handler.get_rgbd_data())
			[CONST.SEED_MESSAGE, var new_episode_seed]:
				episode = new_episode_seed
			[CONST.QUERY_AVAILABLE_FEATURES_MESSAGE]:
				var available_features = observation_handler.get_available_features(player)
				env_bridge.write_available_features_response(available_features)
			[CONST.SELECT_FEATURES_MESSAGE, var feature_names]:
				selected_features = {}
				for feature_name in feature_names:
					selected_features[feature_name] = true
			[CONST.ACTION_MESSAGE, var data]:
				last_action = data
				var stream = StreamPeerBuffer.new()
				stream.data_array = data
				input_collector.read_input_from_pipe(stream)
				is_reply_requested = true
				advance_frame()
				return false
			[CONST.DEBUG_CAMERA_ACTION_MESSAGE, var data]:
				if is_debugging_output_requested():
					debug_logger.current_debug_file.flush()
				if camera_controller.debug_view == null:
					var size = Vector2(
						avalon_spec.recording_options.resolution_x,
						avalon_spec.recording_options.resolution_y
					)
					camera_controller.add_debug_camera(size)

				camera_controller.debug_view.read_and_apply_action(data)
				is_reply_requested = true
				advance_frame()
				return false

			[CONST.CLOSE_MESSAGE]:
				print("CLOSE_MESSAGE received: exiting")
				return true
			_:
				HARD.stop("Encountered unexpected message %s" % [decoded_message])

	# quit if we ever break out of the above loop
	return true


func _get_references_to_clean() -> Array:
	return ._get_references_to_clean() + [env_bridge]
