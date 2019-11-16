# Use this file to config the options for the Deployer lib.

import Config

config :targets, [
  prod: [
    # host to connect to by ssh
    host: "host_address",
    # user to connect under
    user: "user_for_the_host",
    # name of the app to be releases
    name: "your_app_release_name",
    #path where deployer places its configuration on the target host,
    path: "~/some/path/on/the/host",
    # absolute or relative path to the key to use for ssh`
    ssh_key: "~/.ssh/your_key",
    # you can apply tags to each release - when you build a release the `:latest` tag is always added to it and removed from any other release with the same name in the store
    tags: ["some_tag", "another_one"],
    # after deploy the release packet prepared during build is untar'ed on the server, you can execute additional steps after the deploying, before starting the release. It can be ommitted or set to nil
    after_mf: nil # {Module, :function_name, ["arg1", 2, :three]}
  ]
  # ,
  # another_target: [ .... ]
]

# config :groups, [
  # name_of_group: [:prod, :another_target]
  # can_be_many: [:one_host, :another_one]
# ]

config :builders, [
  prod: {Deployer.Builder.Docker, :build, []}
]
