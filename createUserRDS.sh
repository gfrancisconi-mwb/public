#Create user on AWS RDS Mysql with the correct grant
#!/bin/bash

db_user=developers
db_name=eagle
grant_list_dev="SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER, LOAD FROM S3, SELECT INTO S3, INVOKE LAMBDA"
grant_list_prod="SELECT"

function containsElement () {
 local e match="$1"
 shift
 for e; do [[ "$e" == "$match" ]] && return 0; done
 return 1
}

if [ -z "$1" ]
  then
    echo "Missing Environment"
    echo
    echo "Usage: ${0} [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "    --env: Environment (dev, qa, stage, prod)"
    echo "    --service: Service name"
    exit 1
fi

env=$1

ENVS=("dev" "qa" "stage" "prod")
if ! containsElement "$env" "${ENVS[@]}" ; then
    echo "Invalid environment"
    exit 1
fi

aws configure list
echo ""
read -r -p "Are you in correct aws profile ? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then

      DBINSTANCEIDENTIFIER="eagle"
      ENDPOINT_ADDRESS=$(aws rds describe-db-instances \
          --query 'DBInstances[*].[Endpoint.Address]' \
          --filters Name=db-instance-id,Values=${DBINSTANCEIDENTIFIER}-${env}-0 \
          --output text \
          )

      echo "Endpoint Address --> $ENDPOINT_ADDRESS"

      MASTER_USERNAME=$(aws rds describe-db-instances \
          --query 'DBInstances[*].[MasterUsername]' \
          --filters Name=db-instance-id,Values=${DBINSTANCEIDENTIFIER}-${env}-0 \
          --output text \
          )

      echo "Master Username  --> $MASTER_USERNAME"

      MASTER_PWD=$(aws secretsmanager get-secret-value \
          --query '[SecretString]' \
          --secret-id /eagle/secrets/${env}/MYSQL_PASSWORD \
          --output text)

      #echo "Master password  --> $MASTER_PWD"
      #exit

      DEVELOPER_PWD=$(aws secretsmanager get-secret-value \
          --query '[SecretString]' \
          --secret-id /eagle/secrets/${env}/MYSQL_DEVELOPER_PASSWORD \
          --output text)

    

      if [ "$env" = "dev" ] || [ "$env" = "qa" ] 
        then
          grant_list=$grant_list_dev
         else
          grant_list=$grant_list_prod
      fi

      echo "CREATE USER '${db_user}'@'%' IDENTIFIED BY '${DEVELOPER_PWD}';" > /tmp/create_user_developer_${env}.sql
      echo "GRANT ${grant_list} ON ${db_name}.* TO '${db_user}'@'%';" >> /tmp/create_user_developer_${env}.sql      
      echo "FLUSH PRIVILEGES;" >> /tmp/create_user_developer_${env}.sql

      if [ ! ${ENDPOINT_ADDRESS} = "" ] && [ ! ${MASTER_USERNAME} = "" ] && [ ! ${MASTER_PWD} = "" ] && [ ! ${DEVELOPER_PWD} = "" ]
      then
         mysql -A -v -f -h${ENDPOINT_ADDRESS} -u${MASTER_USERNAME} -p${MASTER_PWD} < /tmp/create_user_developer_${env}.sql
         rm /tmp/create_user_developer_${env}.sql
      else
         echo "Error on get parameter from AWS"
      fi
      
else
    echo "exit"
fi