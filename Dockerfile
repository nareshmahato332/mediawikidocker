FROM centos:7
RUN yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm https://rpms.remirepo.net/enterprise/remi-release-7.rpm yum-utils
RUN yum-config-manager --enable remi-php80
RUN yum install php php-common php-opcache php-mcrypt php-cli php-gd php-curl php-mysql php-mbstring php-xml php-intl -y
COPY mediawiki-1.39.1 /var/www/mediawiki
COPY httpd.conf /etc/httpd/conf/
RUN systemctl enable httpd
CMD ["/usr/sbin/init"]
