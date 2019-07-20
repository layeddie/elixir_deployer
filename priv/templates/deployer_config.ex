# Use this file to config the options for Deployer.
%{
  targets: %{
    "prod" => %{
      # host to connect to by ssh
      host: "ec2-18-209-94-98.compute-1.amazonaws.com",
      # user to connect under
      user: "ubuntu",
      # name of the app to be releases
      name: "homelytics",
      #path where deployer places its configuration on th e target host,
      path: "~/homelytics_deployer",
      # absolute or relative path to the key to use for ssh, it can be left ommited or set to nil, in which case you need to pass the flag `-ssh_key` to the task, like `mix deployer.deploy -target=one_host -ssh_key=~/path_to/ssh_key`
      ssh_key: "~/.ssh/aws-ec2.pem",
      # after deploy the release packet prepared during build is untar'ed on the server, you can execute additional steps after the deploying, before starting the release. It can be ommitted or set to nil
      after_mf: nil # {Module, :function_name, ["arg1", 2, :three]}
    }
  }
  # these are groups of hosts defined one the previous section, and it just makes the deployment for all hosts included here, in the order defined. To run you would invoke `mix deployer.deploy -group=name_of_group`
  # groups: %{
  #   name_of_group: [:one_host, :another_one]
  #   can_be_many: [:one_host]
  # }
  # if you want to build on specific host machines, the same as for targets, the after_mfa is called after the build is complete - if no mfa is provided the build tar is transferred back to your local store - check the docs for all options
  # builders: %{
  #   host: "some_address" 
  #   user: "someuser",
  #   path: "/some/path",
  #   ssh_key: "/path/local/to/sshkey",
  #   after_mf: nil
  # }
}
