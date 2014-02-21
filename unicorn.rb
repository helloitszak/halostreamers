dir = File.expand_path(File.dirname(__FILE__))

worker_processes 2
working_directory dir


timeout 30

listen "#{dir}/tmp/unicorn.sock", :backlog => 64

pid "#{dir}/tmp/unicorn.pid"

stderr_path "#{dir}/log/unicorn.stderr.log"
stdout_path "#{dir}/log/unicorn.stdout.log"