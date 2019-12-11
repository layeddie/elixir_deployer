# Deployer

Deployer is a lib to aid in building and deploying elixir releases.

It's built around several tasks to facilitate building and pushing releases to hosts.
Although the long form goal would be to have a lib that is able to handle several different workflows, in what it means and how, both, a release is built and deployed, as of now the only fully working implementations are for building a release tar from a Dockerfile, and pushing that release through ssh to a target host.

It's not yet available on hex  as it's far from complete, to use it add to your project:

```
defp deps do
    [
        {:deployer, git: "https://github.com/mnussbaumer/elixir_deployer.git", only: [:dev], runtime: false}
    ]
end
```

Then do:

```
mix deps.get
mix deployer init
```

The init task will create a folder at the top level of your project, be it a umbrella or regular project, `deployer/`

This folder contains 3 folders:
`release_store` &
`temp` &
`config`:
    - deployer_config.ex
    - deployer_dets
    
`deployer_config.ex` is where you'll write your targets (hosts to deploy) details and builds.
`deployer_dets` shouldn't be removed - it's a DETS table mapping between the actual tarballs stored in `release_store` and tags, date of build, md5hash, metadata that is useful.


Then you should create a Dockerfile responsible for building your release. An example can be found in [here]() (notice that Dockerfile relies on another image, for which the Dockerfile is also provided, which serves as the basis for building the release for an Ubuntu target host).

Lastly configure your `deployer_config.ex` file.

With that in place, assuming you kept the builders `:prod` entry, and that you have Docker running, you could build the release by doing:

`mix deployer build target=prod`

And this will run the Dockerfile you specified, once it's finished it will extract the release and tar it, placing it on the `release_store` and storing the metadata for that release in the DETS table. It will also remove the docker images/containers that result from running that Dockerfile.

Then running 
`mix deployer deploy target=prod` 
will try to deploy a tarball to the host you configured, using the details you specified on the `:targets` config. It will always ask if you want to use the latest release of something, and if not you'll be shown all available releases and asked to choose which one.

To deploy the release it connects through SSH to the host, using the user you provided and the ssh_key you set, and then pushes the release up there. The first time it runs in an host it also creates a remote config file to keep track of what is or not available.
The value you choose for `path` of the release is what the deployer uses to create a folder in your host default folder, this folder will be called `/releases` and contain both the release folders and the symlink to the running folder. You can use relative paths, but usually it's better to provide absolute paths, as relative paths can be finicky.

Once the remote "store" is initialized, the folders created, it uploads the tar, once the tar is uploaded it unpacks it. It creates or replaces the `current` symlink to whatever was this last unpacked tar.

To manage your releases - prunning old releases, deleting old releases you can use:

`mix deployer manage` 

This will start on your local host, showing you all releases you have in store. IT also shows you the commands you can run. You can prune a release by name, where it removes all releases with that name except the last one. You can connect to a remote host, where it will connect through SSH using whatever that target configuration you have, and then you can do the same "prune" older no longer used releases or delete releases etc. Pruning on the remote keeps always the latest but also the current symlinked release in case it's not the latest.




    



