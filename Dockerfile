FROM registry.access.redhat.com/rhscl/ruby-23-rhel7
USER root
# sshd
RUN ["bash", "-c", "yum install -y --setopt=tsflags=nodocs openssh-server ed libicu-devel && \
     yum clean all && \
     sshd-keygen && \
     mkdir /var/run/sshd"]
RUN ls -al /etc/ssh
# add a user that we will replace later 
RUN adduser --system -s /bin/bash -u 1234321 -g 0 git && \ 
   chown root:root /etc/ssh/* /home && \
   chmod 775 /etc/ssh /home && \  
   chmod 660 /etc/ssh/sshd_config && \
   chmod 664 /etc/passwd /etc/group && \
   chmod 775 /var/run && \
   mkdir -p /home/git/data/gls

# Loosen permission bits for group to avoid problems running container with
# arbitrary UID
# When only specifying user, group is 0, that's why /var/lib/mysql must have
# owner mysql.0; that allows to avoid a+rwx for this dir
  
EXPOSE 2022
RUN chmod -R 775 /home/git
# gitlab-shell setup
USER git
COPY . /home/git/gitlab-shell
WORKDIR /home/git/gitlab-shell
RUN ["bash", "-c", "bundle"]

RUN mkdir /home/git/gitlab-config && \
    ## Setup default config placeholder
    cp config.yml.example ../gitlab-config/config.yml
    # PAM workarounds for docker and public key auth
USER root    
RUN sed -i \
          # Disable processing of user uid. See: https://gitlab.com/gitlab-org/gitlab-ce/issues/3027
          -e "s|session\s*required\s*pam_loginuid.so|session optional pam_loginuid.so|g" \
          # Allow non root users to login: http://man7.org/linux/man-pages/man8/pam_nologin.8.html
          -e "s|account\s*required\s*pam_nologin.so|#account optional pam_nologin.so|g" \
          /etc/pam.d/sshd
    # Security recommendations for sshd
RUN sed -i \
          -e "s|^[#]*GSSAPIAuthentication yes|GSSAPIAuthentication no|" \
          -e 's/#UsePrivilegeSeparation.*$/UsePrivilegeSeparation no/' \
          -e 's/#Port.*$/Port 2022/' \
          -e "s|^[#]*ChallengeResponseAuthentication no|ChallengeResponseAuthentication no|" \
          -e "s|^[#]*PasswordAuthentication yes|PasswordAuthentication no|" \
          -e "s|^[#]*StrictModes yes|StrictModes no|" \
          /etc/ssh/sshd_config && \
    echo -e "UseDNS no \nAuthenticationMethods publickey" >> /etc/ssh/sshd_config

RUN rm -f /run/nologin

RUN ln -s /home/git/gitlab-config/config.yml
RUN chmod -R 775 /home/git

USER git

CMD echo -e ",s/1234321/`id -u`/g\\012 w" | ed -s /etc/passwd && ssh-keygen -A && bin/start.sh
