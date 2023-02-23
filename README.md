# How to containerize mediawiki and deploy in k8s cluster and create CI/CD pipeline.

 # Dockerfile
 Dockerfile is is the containerize the mediawiki page and download the required packages


        FROM centos:7
        RUN yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm https://rpms.remirepo.net/enterprise/remi-release-7.rpm yum-utils
        RUN yum-config-manager --enable remi-php80
        RUN yum install php php-common php-opcache php-mcrypt php-cli php-gd php-curl php-mysql php-mbstring php-xml php-intl -y
        COPY mediawiki-1.39.1 /var/www/mediawiki
        COPY httpd.conf /etc/httpd/conf/
        RUN systemctl enable httpd
        CMD ["/usr/sbin/init"]
        
 # Deploy MYSQL in k8s.
    
    # Create pv and pvc. PVs are resources in the cluster. PVCs are requests for those resources and also act as claim checks to the resource.
      
          apiVersion: v1
          kind: PersistentVolume
          metadata:
            name: mysql-pv-volume
            labels:
              type: local
          spec:
            storageClassName: manual
            capacity:
              storage: 11Gi
            accessModes:
              - ReadWriteOnce
            hostPath:
              path: "/mnt/mysqldata"
          ---
          apiVersion: v1
          kind: PersistentVolumeClaim
          metadata:
            name: mysql-pv-claim
          spec:
            storageClassName: manual
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 11Gi

    # Now deploy the mysql using below k8s yaml 
    
            apiVersion: v1
            kind: ConfigMap
            metadata:
              name: mysql-initdb-config
            data:
              initdb.sql: |
                CREATE USER 'wiki'@'%' IDENTIFIED BY 'THISpasswordSHOULDbeCHANGED';
                CREATE DATABASE my_wiki;
                GRANT ALL PRIVILEGES ON my_wiki.* TO 'wiki'@'%';
                FLUSH PRIVILEGES;          
            ---
            apiVersion: v1
            kind: Secret
            metadata:
              name: mysql-secret
            type: kubernetes.io/basic-auth
            stringData:
              password: test1234
            ---    
            apiVersion: v1
            kind: Service
            metadata:
              name: mysql
            spec:
              ports:
              - port: 3306
              selector:
                app: mysql
              clusterIP: None
            ---
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: mysql
            spec:
              selector:
                matchLabels:
                  app: mysql
              strategy:
                type: Recreate
              template:
                metadata:
                  labels:
                    app: mysql
                spec:
                  containers:
                  - image: mysql/mysql-server:latest
                    name: mysql
                    env:
                      # Use secret in real usage
                    - name: MYSQL_ROOT_PASSWORD
                      valueFrom:
                        secretKeyRef:
                          name: mysql-secret
                          key: password
                    ports:
                    - containerPort: 3306
                      name: mysql
                    volumeMounts:
                    - name: mysql-persistent-storage
                      mountPath: /var/lib/mysql
                    - name: mysql-initdb-config
                      mountPath: /docker-entrypoint-initdb.d          
                  volumes:
                  - name: mysql-persistent-storage
                    persistentVolumeClaim:
                      claimName: mysql-pv-claim
                  - name: mysql-initdb-config
                    configMap:
                      name: mysql-initdb-config    
   

# Mediawiki Deployment file.

              apiVersion: apps/v1
              kind: Deployment
              metadata:
                labels:
                  run: wiki-mysql
                name: wiki-mysql
              spec:
                replicas: 1
                selector:
                  matchLabels:
                    run: wiki-mysql
                strategy:
                  rollingUpdate:
                    maxSurge: 1
                    maxUnavailable: 1
                  type: RollingUpdate
                template:
                  metadata:
                    labels:
                      run: wiki-mysql
                  spec:
                    containers:
                    - image: container_registry_url/<name>:buildno
                      # eg: - image:masterdockerimages.azurecr.io/nginx:azure
                      securityContext:
                        privileged: true
                      imagePullPolicy: Always
                      name: wiki-mysql-container
                      ports:
                      - containerPort: 80
                        protocol: TCP
                      resources:
                        limits:
                          cpu: 1
                          memory: 1Gi
                        requests:
                          cpu: 1
                          memory: 1Gi
                      terminationMessagePath: /dev/termination-log
                    restartPolicy: Always
                    terminationGracePeriodSeconds: 30
              ---
              apiVersion: v1
              kind: Service
              metadata:
                name: wiki-mysql
              spec:
                type: ClusterIP
                ports:
                - name: http
                  port: 80
                  protocol: TCP
                  targetPort: 80
                selector:
                  run: wiki-mysql
              ---
              apiVersion: autoscaling/v2beta2
              kind: HorizontalPodAutoscaler
              metadata:
                name: wiki-mysql
              spec:
                maxReplicas: 5
                minReplicas: 2
                scaleTargetRef:
                  apiVersion: apps/v1
                  kind: Deployment
                  name: wiki-mysql
                metrics:
                - type: Resource
                  resource:
                    name: cpu
                    target:
                      type: Utilization
                      averageUtilization: 80

# Now Let configure Jenkins CI/CD Job using below jenkinsfile, We can use anykind of script or any other CI/CD tool.

          node {
              try {
                      def application = 'mediawiki'
                      def environment = 'demo'
                      def kubernetes_namespace = 'demo'
                      def branchname = 'main'

                stage('Clone repository') {
                              git([url: 'https://github.com/nareshmahato332/mediawiki.git', branch: "${branchname}", credentialsId: 'github_cred'])
                  }

                      stage('wikidownload') {
                          sh ''' 
                             wget https://releases.wikimedia.org/mediawiki/1.39/mediawiki-1.39.1.tar.gz
                             wget https://releases.wikimedia.org/mediawiki/1.39/mediawiki-1.39.1.tar.gz.sig
                             tar -zxf mediawiki-1.39.1.tar.gz
                             '''
                      }

                      stage('Build image') {
                          app = docker.build("${application}_${environment}",".")
                      }

                      stage('Push image') {
                          docker.withRegistry('container_registry_url', 'registry_authentication') {
                              app.push("${kubernetes_namespace}_${env.BUILD_NUMBER}")
                          }
                      }            
                       stage('Deploy') {)
                           sh '''
               echo 'Deploy Stage Started !!'

               kubectl config use-context <CONTEXT_NAME> ## k8s cluster context name where we want to deploy the application

                     sed -i 's/buildno/$BUILD_NUMBER/g' mediawiki-deployment.yaml'"
                           kubectl apply -f mysql-pv-pvc.yaml -n <namespace>
               kubectl apply -f mysql-deployment.yaml -n <namespace>
               kubectl apply -f mediawiki-deployment.yaml -n <namespace>

                           echo 'Deploy Stage Completed Successfully !!
               '''
                      }

                      stage('Remove old images') {
                          sh("docker rmi -f container_registry_url/${application}_${environment}:latest ")
                     }

                     stage('Notifications') {
                          echo 'Notification sent to build owners with deployment status !!'
                     }
                  } catch (e) {
                      currentBuild.result = "FAILED"
                      throw e
                  }
              }


# Now it is successfully deployed and if we want to acess mediawiki page with some domain name then we need to to configure ingress also.
# I am accessing directly with k8s pod IP.

<img width="1542" alt="image" src="https://user-images.githubusercontent.com/63515033/220957596-8d18597f-f2de-4f2e-92fb-14b8052070c1.png">

# Now click setup the wiki and Go to connect to database page.

<img width="1306" alt="image" src="https://user-images.githubusercontent.com/63515033/220958616-a937bc93-64ff-4ea0-a90e-92074236dc6d.png">

# Enter your DB Hostname, In my case since i have deployed in k8s, I am access with k8s internal DNS name.

<img width="417" alt="image" src="https://user-images.githubusercontent.com/63515033/220960459-2fd90986-3af6-4301-bc3e-3a786266ecae.png">

# Enter the required databases details 

<img width="469" alt="image" src="https://user-images.githubusercontent.com/63515033/220960210-1aa2079e-d926-4caf-99d3-65e83803ed45.png">

Once Database is connected, complete the setup.

Cheers!!!!






 
