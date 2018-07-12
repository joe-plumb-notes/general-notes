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

## docker notes
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
- 

## Setup

## Running/managing docker containers

## Threads vs Processes

  
</p>
</details>

