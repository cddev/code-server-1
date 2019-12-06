FROM node:10.16.0
ARG codeServerVersion=docker
ARG vscodeVersion
ARG githubToken

# Install VS Code's deps. These are the only two it seems we need.
RUN apt-get update && apt-get install -y \
	libxkbfile-dev \
	libsecret-1-dev

# Ensure latest yarn.
RUN npm install -g yarn@1.13

WORKDIR /src
COPY . .

RUN yarn \
	&& MINIFY=true GITHUB_TOKEN="${githubToken}" yarn build "${vscodeVersion}" "${codeServerVersion}" \
	&& yarn binary "${vscodeVersion}" "${codeServerVersion}" \
	&& mv "/src/binaries/code-server${codeServerVersion}-vsc${vscodeVersion}-linux-x86_64" /src/binaries/code-server \
	&& rm -r /src/build \
	&& rm -r /src/source

# We deploy with ubuntu so that devs have a familiar environment.
FROM ubuntu:18.04

RUN apt-get update && apt-get install -y \
	openssl \
	net-tools \
	git \
	locales \
	sudo \
	dumb-init \
	vim \
	curl \
	wget \
	gpg \ 
	lsb-release \
    add-apt-key \
    ca-certificates \
	pkg-config \
    build-essential \
  && rm -rf /var/lib/apt/lists/*

# Azure CLI
RUN curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update && apt-get install --no-install-recommends -y azure-cli \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
RUN echo "deb [arch=amd64] https://packages.microsoft.com/ubuntu/18.04/prod $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/microsoft-prod.list
RUN apt-get update && apt-get install --no-install-recommends -y \
   libunwind8 \
   dotnet-sdk-3.1 \
   && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
# We cannot use update-locale because docker will not use the env variables
# configured in /etc/default/locale so we need to set it manually.
ENV LC_ALL=en_US.UTF-8 \
	SHELL=/bin/bash

RUN adduser --gecos '' --disabled-password coder && \
	echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

USER coder

# Setup Uset .NET Environment
ENV DOTNET_CLI_TELEMETRY_OPTOUT "true"
ENV MSBuildSDKsPath "/usr/share/dotnet/sdk/2.2.402/Sdks"
ENV PATH "${PATH}:${MSBuildSDKsPath}"

# Setup User Visual Studio Code Extentions
ENV VSCODE_USER "/home/coder/.local/share/code-server/User"
ENV VSCODE_EXTENSIONS "/home/coder/.local/share/code-server/extensions"

# We create first instead of just using WORKDIR as when WORKDIR creates, the
# user is root.
RUN mkdir -p /home/coder/project
# To avoid EACCES issues on f.ex Crostini (ChromeOS)
RUN mkdir -p /home/coder/.local/code-server

RUN mkdir -p ${VSCODE_USER}
COPY --chown=coder:coder settings.json /home/coder/.local/share/code-server/User/

# Setup .NET Core Extension
RUN mkdir -p ${VSCODE_EXTENSIONS}/csharp \
    && curl -JLs https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode/vsextensions/csharp/latest/vspackage | bsdtar --strip-components=1 -xf - -C ${VSCODE_EXTENSIONS}/csharp extension
# Setup Alternate Debugger for .Net
RUN curl -sL https://github.com/Samsung/netcoredbg/releases/download/latest/netcoredbg-linux-master.tar.gz | tar -zx -C /home/coder
ENV PATH "${PATH}:/home/coder/netcoredbg"

WORKDIR /home/coder/project

# This ensures we have a volume mounted even if the user forgot to do bind
# mount. So that they do not lose their data if they delete the container.
VOLUME [ "/home/coder/project" ]

COPY --from=0 examples /home/coder/examples
COPY --from=0 /src/binaries/code-server /usr/local/bin/code-server

EXPOSE 8080

ENTRYPOINT ["dumb-init", "code-server", "--host", "0.0.0.0"]
