defmodule JobProcessor.BashRendererTest do
  use ExUnit.Case, async: true

  alias JobProcessor.BashRenderer
  alias JobProcessor.Task

  test "starts with the Bash shebang" do
    assert BashRenderer.render([task("echo hello")]) =~ "#!/usr/bin/env bash\n"
  end

  test "renders commands in the supplied order" do
    tasks = [task("touch /tmp/file1"), task("cat /tmp/file1")]

    assert BashRenderer.render(tasks) ==
             "#!/usr/bin/env bash\ntouch /tmp/file1\ncat /tmp/file1\n"
  end

  test "preserves commands verbatim" do
    command = "echo 'Hello World!' > /tmp/file1"

    assert BashRenderer.render([task(command)]) == "#!/usr/bin/env bash\n#{command}\n"
  end

  test "includes a trailing newline" do
    assert String.ends_with?(BashRenderer.render([task("echo hello")]), "\n")
  end

  test "renders an empty task list as a valid script" do
    assert BashRenderer.render([]) == "#!/usr/bin/env bash\n"
  end

  defp task(command) do
    %Task{name: "task", command: command}
  end
end
