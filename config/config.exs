import Config

config :job_processor,
  port: if(config_env() == :test, do: 0, else: 4000)
