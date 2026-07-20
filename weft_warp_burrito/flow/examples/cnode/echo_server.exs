pid =
  spawn(fn ->
    receive do
      {from, msg} when is_pid(from) ->
        IO.puts("echo_server got: #{inspect(msg)} from #{inspect(from)}")
        send(from, {:pong, msg})
    end
  end)

Process.register(pid, :echo_server)
IO.puts("echo_server registered as #{inspect(pid)} on #{node()}")
:timer.sleep(:infinity)
