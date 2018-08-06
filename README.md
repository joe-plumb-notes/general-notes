# general-notes

## python notes
<details><summary>python notes</summary>
<p>
  
### general functions

### pandas
#### init
` import pandas as pd`
#### notes
- [`pandas.melt`](https://pandas.pydata.org/pandas-docs/stable/generated/pandas.melt.html) - function to unpivot a dataframe into a format where one or more columns are identifier variables (id_vars), while all other columns, considered measured variables.
- [`.nunique()`](http://pandas.pydata.org/pandas-docs/stable/generated/pandas.core.groupby.SeriesGroupBy.nunique.html) - returns count of unique values from a column, e.g. `df1['Region'].nunique()`

### numpy
#### init
`import numpy as np`
#### notes
- np.zeros((y,x)) - function to generate matrix of zeros(vertical, horizontal)
- np.random.rand(2,5) - random 2x5 matrix with all numbers between 0 and 1

### mpl
#### init
```
import matplotlib as mpl
import matplotlib.pyplot as plt
```
#### notes
- </p>
</details>

## Docker notes
taken from https://www.safaribooksonline.com/videos/learning-docker/9781491956885
<details><summary>docker notes</summary>
<p>
  
## Containerization/OS level virtualization
- Linux containers are considered operating system level virtualization, which provides isolated view of processes, user space, and file system for the user or owner. Containers share the kernel of the Linux host they are running on. OS Virtualization is not new despite the rise in interest via docker, and have existed in similar forms in FreeBSD Jails, Solaris Zones, and LXC.
- Differences/similarities between containers and VMs?
    - Both require host OS. VMs can run on a variety of OS
    - VMs require a hypervisor - a piece of software that can create, run, destroy, and monitor VMs. Type 1 run directly on host machine hardware, ESX and Xen are popular versions. Type 2 hypervisor runs as software on top of the host OS - VMWare and VirtualBox are commonly user. VMs can run any guest OS they choose, regardless of the host OS. VMs require full OS install, which means they incur the same startup and shutdown times as on bare metal (perhaps longer). Can run many processes, and have variety of network and file system configurations.
    - Containers do not require hypervisor, but a container engine. This could be FreeBSD jails, Solaris Zones, Rocket, or Docker. They also have significatly smaller overheads - because they share the kernel with the host OS, they can start and stop extremely fast. A container typically contains a single processes and its dependencies. Startup time is determined by the amount of time the process takes to start, making them very efficient for clustered cloud like environments. As they share the host OS kernel, they must use the same OS. Docker containers must run linux distros.
- docker is a tool built as an abstraction on top of linux containers, and allows for easy, programmatic creation and distribution of container images, as well as creating and deploying containers. Provides CLI and HTTP interfaces to make it easy to manage and automate, and creates a homogenous system for running apps. Containers ship with the dependencies baked in, so the deployment is the same regardless of where you deploy.

## Architecture
- We know docker is an abstraction built on top of lower level container technologies, which provides a simple cli and http interface to create and publish container images, and to run these themselves. It provides a way to package an application and all system dependncies into a standardized unit (Docker image). 
- It is a tool, but also encompasses an ecosystem of other tools and services, e.g. DockerHub (central public repo of docker images).
- Widley used deployment mechanisim for applications because of the guarantee the container will always run the same regardless of the environment, giving devs parity across dev, test, and prod.

## Setup
- I started by accidentally installing Docker CE in an Ubuntu 16.04 VM following the instructions in the docker docs. I then realised this is not what the course was asking me to do, so followed the docs to install Docker Engine too https://docs.docker.com/cs-engine/1.12/#install-on-ubuntu-1404-lts-or-1604-lts
- Automatic starting of the docker daemon is achieved using systemd `sudo systemctl enable docker`
- Check docker working using sample container `sudo docker run rickfast/hello-oreilly`
- Adding a user to the docker group prevents requirement to run all docker commands with sudo `sudo usermod -aG docker $USER` (log out and log back in to have changes take)
- Another test container `docker run -p 4567:4567 -d rickfast/hello-oreilly-http` runs a web server on port 4567 that returns the 'Hello O'Reilly!' message.

- OS's that aren't Linux cannot run docker natively as docker requires a Linux compatible kernel. Used to have `boot2docker` which was a stripped down Linux image with docker installed, which enabled people running OSX to issue docker commands to a remote docker daemon in a VM. More recently, a series of useful docker tools have been packaged into Docker Toolbox, which can be installed using a simple installer. `boot2docker` is still used, but it is managed by `docker-machine`. *NB: Docker Toolbox is now a legacy desktop solution that has been superceded by Docker for Mac and Docker for Windows. The Docker for Windows application requires Windows 10 which I do not have, so I will continue with docker toolbox and my ubuntu VM side by side*
- starting docker toolbox using the `Docker Quickstart Terminal`, which launches a fully configured shell, starting a docker host in virtualbox.
- `default` machine will start with IP `192.168.99.100` - this is the IP of the docker machine. On Linux, this runs on `localhost`

## Docker Machine
- Ships with toolbox, allows us to use docker with non-linux based OS's, and launch and manage multiple docker instances from the host machine. 
- I quickly installed `docker-machine` in my ubuntu VM following [the docs](https://docs.docker.com/machine/install-machine/#install-machine-directly). I think this is going to be a better and easier fit as the rest of the course is on Mac OS. *NB: doing this introduced an issue as I had [conflicting graph-drivers](https://github.com/moby/moby/issues/22685). `systemctl edit docker.service` allowed me to configure the docker startup process and set the `-s` arg to `overlay` which resolved\* the issue*
- \* This did not resolve the issue. I was able to get the docker daemon started but still encountered problems. I uninstalled and reinstalled Docker CE. Then tried creating my own `docker-machine` but this is failing with `Error creating machine: Error waiting for machine to be running: Maximum number of retries (60) exceeded` - _but that's ok because I can run docker containers natively because I'm in Linux_ right ok the penny dropped, there we go, move along ..
- see which hosts are running using `docker-machine ls`
- if working with docker machine, set the machine you want to issue commands to with `eval $(docker-machine env $docker-machine)`. Get the IP of this machine by issuing `docker-machine ip $MACHINENAME`. Stop the machine with `docker-machine stop $MACHINE`
- Docker machine is good because it enables people to use docker regarless of their host OS. Alos a nice tool for launching multiple docker hosts (these can be in the cloud as well as locally)

## Docker Hub
- For distributing docker images - official central registry. There are other registerys, and you can set up your own (artifactory, docker trusted registy).
- Need a docker hub account to push your own into the registry. 

## Running/managing docker containers
### Getting Started
- Containers typically wrap a single process, and the lifetime of the container is typically tied to the time it takes to run the process assigned to pid 1 within. The command run by the container can be specified by the container, or the user running it.
- e.g. of specifying the command run by the container `docker run ubuntu pwd` - ubuntu container does not specify a command to be run, so we can run `pwd`. The container will only live for the time it takes to run this command, make it useful for taks that require a specific setup or environment.
- output is different as the container has it's own isolated view of the operating environment - the ubuntu container has it's own user id space, filesystem, process trees, and networking.
- How can we investigate the inside of a container without running single commands? `i` flag runs in interactive, and `-t` assigns a terminal (specify the shell you want as well) `docker run -i -t ubuntu /bin/bash`
- uuid is the hostname of the container - a unique hash, also the container id.
- has typical file system, but only two processes running (`ps` and `bash` - `bash` is pid 1, which means the containers existance is bound to this process). Can end the container by running `exit`, which quits the bash session and also the container.

### Different ways to run containers
- specifying just the image name will just run that image. This will run the default command in the image. Can override the default by adding another argument when issuing `docker run`. Additional args after this are passed as arguments to the override command, i.e. `docer run ubuntu ls -l`. Any number of commands can be passed in the command arguments.
- running a long-iving container from the command line pushes the output of this container to stdout - not ideal as container will exit if we close terminal, ctrl+c, etc. In production scnarios we want the containers to run as background processes. To run them as background processes, use `-d` (detached). This prints a container id to stdout which can be used to execute actions against that container.
- `docker ps` lists all running containers.
- Containers can be referenced by image id or name, and if you dont explicitly name your container, docker will auto-assign one. `--name` to name your container - names are useful if you're running a lot of instances of the same container on a docker host, or if using a bridged network, as containers use names to communicate (see networking)
- `docker stop` to stop the container, don't need to write the whole id
- `docker restart` to restart a container (takes name)

### Containerized Web Applications
- Long-lived web apps are a common use case. Will run a web app which performs lookup in a key:value store, redis.
- First, run redis `docker run -d -P --name redis redis`
- Then start web app - this will need to be able to connect to redis to store and retrieve data. 
- `docker --link` to connect containers together - allow continers to find each other by ip and port. docker containers are linked by name, and docker injects a set of env vars into the container that can be used to connect them.
- `docker run --link redis -i -t ubuntu /bin/bash` to start an ubuntu container and link to redis .. looking at `env`, cna see `REDIS_PORT_6379_TCP_ADDR=172.17.0.2`, which gives the IP of the redis container. This format/naming covention ($NAME_PORT_$PORT_TCP_ADDR) means we have to know the name of the container and the port, to connect to it. The web app uses this env variable to connect to redis, and retrieve and store data. 
- Run and link the web app to redis .. `docker run -d --link redis --name web rickfast/oreilly-simple-web-app`
- Docker links are *deprecated*
- Need to map the port using `-p` on container startup - doesn't matter that the application in the container is bound on 4567, we cannot access it on the docker host without mapping the port. first is port on docker host, second is container port to map. So above command becomes `docker run -d --link redis --name web -p 4567:4567 rickfast/oreilly-simple-web-app`
- _What if deploying a web app on a machine and we dont know what ports are available?_ Cant be guaranteed a well known port for every appliaction .. `-P` binds all exposed ports to a randomly availbale port on the docker host - v useful for a dymanic mutlitenant environment. Once used, can use `docker ps -l` which lists the last started container, and you can see the port .. can also use `docker port $NAME` which tells the port that the container is available at on the docker host.

### Configuring Containerized Applications
- Previously would use configuration files to configure server application using tools like chef or puppet. Templatize a config file and drop it on the server before the application launches. Docker image is pre-baked, so we dont necesserily want another layer with environment specific configuration, which would require separate image artifacts for the environment our container would run in.
- Preferred config method for containerized apps is to pass in at launch time, in the form of standard environment variables.
- This puts environment configuration burden on the launcher - `-e` flag enables this. Each env variable must be set using it's own `-e` flag
```
joe@ubuntu:~$ docker run -e "HELLO=JOE" ubuntu /bin/bash -c export
declare -x HELLO="JOE"
...
```
- `docker inspect` gives details about the container

### Container Lifecycle
- `docker restart` runs the same container rather than starting a new one. Discussed graceful shutdown of containers and allowing time for containers to do so, using the `docker stop --time` param.
- If something causes a container to exit, can use the `--restart` policy flag to automatically case it to restart if it exits. Takes a number of args (always, unless stopped (only restart if stops unexpectedly), on failure (if exists with non-0 code) `docker run -d -p 4567:4567 --name timebomb --restart unless-stopped rickfast/oreilly-time-bomb`. To make it not restart, explicity stop it or kill it ourself. 

### Debugging Containers
- Can configure docker to output logs to logging applications (fluentd, splunk). Withg access to the docker host, there are a number of ways to debug a container.
  - see which containers are running `docker ps`, to see what is running. `ps -a` to see stopped containers. `-l` will show the last run container.
  - output of a container i.e. logs `docker logs $NAME` show the most recent logger output. `-f` to follow the logs in the terminal until ctrl+c.
  - Local IP/other information about the container? `docker inspect` give json payload of info about the container. Can extract information from here using the `--format` flag, e.g. `docker inspect --format='{{.NetworkSettings.IPAddress}}' redis`. This uses Go's template support. dot notation represents the json properties, where `NetworkSettings` is top level object, containing field `IPAddress`.
  - Get into container using `-i` and `-t` as we saw earlier .. however this isn't incredibly useful as we're starting a new copy of the container with /bin/bash running as pid 1 .. so how can we debug if it's already running? `docker exec` will enable to run a secondary process in the container `docker exec -i -t redis /bin/bash`
  - Centralised logging and debugging should be used in production to manage.
  
## Docker Images
- Building and sharing our own images is where it gets interesting!
- Packaging your own production applications is a major use case for docker images. Container must only contain linux libraries and binaries. Flavor will dictate which libraries and binaries it will use. Need to map `flask` port to the docker host in order to expose it. (see _Containerized Web Applications_ section above for more on this)
- Docker images are built from layers, which are immutable (non-changing), similar to a git commit. These aren't changed, we just create new ones. Always re-use layers that don't change, and if we do diverge, we create new layers.
- Images are created by running containers, changing their state, and then saving the new state to disk. Only the differences introduced in the new state are saved, which means the state can be applied or reverted from the layer below. Preferred method for applying these changes is via the `dockerfile`, a list of instructions to be performed on an image to produce new layers. Each layer correspondes to an instruction from the dockerfile. Dockerfile ends up looking like:
```
FROM ubuntu:15.10
RUN apt-get install python
RUN pip install flask 
ADD app.py # add source code from my machine to the container using ADD
EXPOSE 5000
ENTRYPOINT python app.py # default coimmand to run so user doesn't need to worry about image internals.
```
- Can then put this in version control and treat it like any other code - version it, create automated builds to push and publish images hen the dockerfile changes. 

### ... on Docker Hub
- Easiest way to find existing images. Search, find .. description of what the image contains, size, etc. 
- Alpine Linux, lightweight base image rather than using ubuntu or fedora (bloated). Info on usage and config. 
- Official repos have no username (i.e. single contributor). Curated by docker, follows best practices inc. security. Offial images are best, kept up to date, etc.. Star = like, remind, save etc. 
- Tags are like versions. `latest` tag typically attached, will default to this. 
- unsurprisingly, `docker push` allows 

## building images
- Any can be used as a base, so depends what you want to build. 
- `docker search` to search, `docker images` to see what is available on the docker host
- can create images from a running container, or create using dockerfile - second is preferred as can be versioned and reproduced
```
docker run -i -t alpine /bin/sh
apk update
apk add nodejs
mkdir average
cd average
vi average.js
```
- add this script
```
#!/usr/bin/env node
var sum = 0;
var count = 0;
process.argv.forEach(function (val, index, array) { 
    if(index > 1) {
        sum += parseInt(val);
        count ++;
  }
});
console.log(sum / count);
```
- then give permissions, and test
```
chmod +x average.js
./average.js 3 4 5
```
- Can now commit these changes to our running container which will create a new image containing these changes. To commit them, we need a container ID, which is the same as the hostname
- To commit the changes, use `docker commit`. Takes a few flags - `-m` for commit messages. _This is an inefficient way to create docker images._
```
joe@ubuntu:~$ docker commit -m "installed node and wrote average app" 3cf4a81f2e02
sha256:9a80c75602aec13f50f37747534b28b2d5ac649c58fe24c1ff3febb6e24df537
joe@ubuntu:~$ docker run 9a80 average/average.js 3 4 5
4
```
- this approach has a number of challenges though .. cant easily specify node as the default entry point or command for the container, so have to know and care about the name of the program, and its location on the filesystem. No artifact that describes how it was created. Infrastructure as cade gives visibility into the internls of the servers, and gives ability to change and test like normal sw. 

### docker build
- relies on dockerfile, which specifies the instructions to build the image. The commands we ran above can be specified in the dockerfile, which would give a shareable, reproducabale and automatable recipe to build the image. Each line is an atomic commit, and each change is cached as the image builds. 
- changing an instruction in the dockerfile will only cause the layers at and after the change to be rebuilt. So you dont have to start from scratch every time you build.
- `FROM` is always first - define the base image.
- `MAINTAINER` defines the owner - no impact on how the container runs.
- `docker build .` to run the Dockerfile from current wd. Can see the image IDs printed below each step in the build process
- Intermediate containers are removed as each step is run in a container, and the container is commited to create the new image.
- `RUN apk update && apk add nodejs` update and add on the same line, to have both happen in one atomic commit
- to add a file to the building docker image, it must reside in the same dir, or one below.
- `WORKDIR` sets current working dir for build 
- `ENTRYPOINT` defines the main process that will run in the container. The command specified here is pid 1. entrypoint is specified as json list, called exec form. this does not invoke command cell, so cannnot include env variables to be interpolated in the command. With the entrypoint specified, arguments passed in when `docker run` is executed are passed to the entry point as arguments
- `docker build -t` to tag (i.e. name) the container

### web application images

### COMMAND (CMD) and ENTRYPOINT
- 2 ways of defining a default execution in a Dockerfile.
- For a container to be runnabale without specifying an executable at the end of the docker run command, the _Dockerfile_ that produced the container image will need one or the other instruction at the end.
-  Without one or the other in the Dockerfile, attempting to run a docker container without a command will result in an error.
- Issuing a command will override the `CMD` instruction from the dockerfile.
- `ENTRYPOINT` defines the default executable for the image - main difference is that this executable cannot be overridden by passing in a command at the end of `docker run` - additional arguments are passed to the entrypoint as arguments.
- `ctrl+c` sends sigterm command to container - since the ping command is pid 1 the container shuts down.
- ENTRYPOINT is specified as a json list - this is known as exec form - this runs the command directly, without using a shell, which means it will always be pid 1, and shut down gracefully using sig term.
- Shell form can be specified too - command token separated by spaces, which runs your command in shell. That means environment variables can be resolved in the command, for example `CMD echo $PATH`

### Build triggers
- Some images include instructions to only be run if the image is used as a base image. Specify commands that only specify for downstream build using the `ONBUILD` instruction. Many official images provide this that will auto-add code to the image, which can make usage much easier.

# Threads vs Processes

  
</p>
</details>

<details><summary>k8s notes</summary>
Notes from reading 'Kubernetes in Action', Marko Lukša (Manning)
<p>

# Intro
- Automation - which includes
automatic scheduling of those components to our servers, automatic configuration,
supervision, and failure-handling. This is where Kubernetes comes in.
- Type 1 hypervisors don't use a host OS. Type 2 do.
- TODO: read about x86 architecture and how kernel issues and performs instructions on CPU
- Benefit of VMs is the full isolation they provide, as each VM runs its wn kernel - containers are all calling the same kernel which can pose a security risk.
- When running a great number of isolated processes on the same machine, containers are a much better choice because of the low overheads - each VM has to run it's own set of system services, which containers do not as they run in the same OS. Containers also require no booting - a process run in a container starts up immediately.
- _Linux Namespaces_ and _control groups_ `cgroups` are the mechanisms used to isolate processes in containers. _Namespaces_ make sure each process sees its own view of the system, and cgroups limit the amount of resources the process can consume,
- System has as master node and _n_ worker nodes. When a list of apps is submitted to the master, k8s deploys them to the cluster of worker nodes. The node it lands 
</p>
</details>

