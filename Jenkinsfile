
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
		 
	         sed -i \"s/buildno/${env.BUILD_NUMBER}/g\" mediawiki-deployment.yaml'"
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
