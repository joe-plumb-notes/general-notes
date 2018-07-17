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

## Threads vs Processes

  
</p>
</details>

