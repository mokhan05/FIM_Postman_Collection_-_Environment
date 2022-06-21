#!/bin/bash
rm -rf output > /dev/null
rm -rf request.json > /dev/null
rm -rf finaloutput > /dev/null

##Install jq if not installed already
#if ! rpm -qa | grep -qw jq; then yum -y install jq; fi

echo ""

##Taking credentials to generate auth token

read -p "Enter the Pod e.g gateway.qg1.apps.qualys.in: " pod
read -p "Enter Pod's username: " usr
read -s -p "Enter Pod's password: " pass
echo ""
echo ""

##Generating Auth Token

# token=$(curl -s -X POST https://gateway.$pod.apps.qualys.com/auth -d "username=$usr&password=$pass&token=true" -H "Content-Type: application/x-www-form-urlencoded")
token=$(curl -s -k -X POST https://$pod/auth -d "username=$usr&password=$pass&token=true" -H "Content-Type: application/x-www-form-urlencoded")


###Verifying the credentials

auth=$(echo "$token" |  grep "authentication_exceptions")

if [ -n "$auth" ]
then
        echo -e "\e[1;31mAuthentication Failed\e[0m: Username or Password is incorrect"
        exit 1
#elif [ -z "$token" ]
#then
#        echo -e "\e[1;31mAuthentication Failed\e[0m: Not able to generate token"
#        exit 1
else
        echo "Authentication Successful"

fi

sleep 1s

#########################################################
#Fetching the List of Profiles for this Pods subscription
#########################################################

echo "{" >> request.json
echo "\"attributes\": \"name,id,status\"," >> request.json
echo "\"pageSize\": \"100\"" >> request.json
echo "}" >> request.json

# pinfo=$(curl -s  -X POST https://gateway.$pod.apps.qualys.com/fim/v3/profiles/search -H "authorization: Bearer $token" -H 'content-type:application/json' -d @request.json)
pinfo=$(curl -s -k -X POST https://$pod/fim/v3/profiles/search -H "authorization: Bearer $token" -H 'content-type:application/json' -d @request.json)

##Removing the request file as same will be created by other APIs as well
rm -rf request.json > /dev/null

echo "$pinfo" | grep -v -E "({|})" | sed 's|"||g;s|,$||g'|sed 's/^ *//g'|sed ':a;N;$!ba;s/\n/\t/g'| sed 's|name :|\nname :|g' | grep -v "^$" | sed 's|name :||g;s|id : ||g;s|status :||g' | sed 's/^ *//g' > profile_info

echo ""
echo -e "FIM Profiles for this subscription along with their details such as name, id & status are saved in the file \e[1;33mprofile_info\e[0m"
echo ""
echo "Following is the list of Activated FIM Profiles"
echo ""
cat profile_info | grep -w "ACTIVATED" | tee active_profiles

##################################################
#Fetching Event Count on the basis of Profile name
##################################################

#read -p "Enter the Profile against which Event details are required: " profile
#read -p "Enter the Profile ID: " pid
echo ""
echo -e "\e[1;33mWarning:\e[0m In order to \e[1;31mnot\e[0m to fetch all the data Date-Time range filter should be provided"
echo -e "Format for providing the Date-Time range filter is as follows: \e[1;33mdateTime:['2020-07-29T18:30:00.000Z'..'2020-08-28T18:29:59.999Z']\e[0m"
echo ""
read -e -p "Provide the Date-Time range filter. Press <Enter> if filter not needed: " dtrange
# rdtrange=$(echo " and $dtrange")

while read line
do
        rm -rf  request.json
        profile=$(echo "$line" | awk -F'\t' {'print $1'})
        pid=$(echo "$line" | awk -F'\t' {'print $2'})
        if [ -n "$dtrange" ]
        then
                rdtrange=$(echo " and $dtrange")
        
                echo "{" >> request.json
                echo "\"filter\":\"profile.name:'$profile'$rdtrange\"," >> request.json
                echo "\"groupBy\":[\"profiles.rules.type\",\"profiles.rules.id\"]" >> request.json
                echo "}" >> request.json

        else
                #echo -e "\e[1;31m--\e[0m"
                echo "{" >> request.json
                echo "\"filter\":\"profile.name:'$profile'\"," >> request.json
                echo "\"groupBy\":[\"profiles.rules.type\",\"profiles.rules.id\"]" >> request.json
                echo "}" >> request.json

        fi

        # curl -s -X POST https://gateway.$pod.apps.qualys.com/fim/v2/events/count -H "authorization: Bearer $token" -H "content-type:application/json" -d @request.json > reqfile.json
        curl -s -k -X POST https://$pod/fim/v2/events/count -H "authorization: Bearer $token" -H "content-type:application/json" -d @request.json > reqfile.json

        jq . reqfile.json > countfile
        event_count=$(cat countfile | grep -E "file|directory")
                
        function_process()
        {
                cat countfile | sed 's|"||g;s|,||g'| grep -E -v "(file:|directory|\{|\}|^$)"| sed 's/^ *//g;s|:||g' > ruleid_count
                # curl -s -X POST https://gateway.$pod.apps.qualys.com/fim/v3/profiles/$pid/exportjson -H "authorization: Bearer $token" -H 'content-type:application/json' > pdata.json
                curl -s -k -X POST https://$pod/fim/v3/profiles/$pid/exportjson -H "authorization: Bearer $token" -H 'content-type:application/json' > pdata.json
                #jq . pdata.json > profile_data
                #jq .rules pdata.json | jq 'map( {(.name): .id} )' | sed 's|"||g;s|{||g;s|},||g;s|}||g;s|\[||g;s|\]||g;'| sed 's/^ *//g' | grep -v "^$" | awk -F':' '{print $1"\t"$2}' | awk '{ gsub(/[ ]+/,"-"); print }' > ruleid_name
                jq .rules pdata.json | jq 'map( {(.name): .id} )' | sed 's|"||g;s|{||g;s|},||g;s|}||g;s|\[||g;s|\]||g;'| sed 's/^ *//g;s|: |~~|g' | grep -v "^$" | awk -F'~~' '{print $1"\t"$2}'|awk '{ gsub(/[ ]+/,"-"); print }' > ruleid_name
                
                while read line
                do
                        id=$(echo "$line" | awk  '{print $1}')
                        num=$(echo "$line" | awk '{print $2}')
                        var=$(cat ruleid_name | grep "$id" )
                        name=$(echo "$var" | awk '{print $1}')
                        if [[ -n "$var" ]]
                        then
                                echo -e "$profile\t$id\t$name\t$num" >> output
                        else
                               echo -e "No rule name found for the rule id: $id - Please check this id and corresponding rule in your subscription"
                        fi

                done < ruleid_count

                total=$(cat output |grep -P "$profile\t" |awk -F'\t' '{s+=$4} END {print s}')
                echo -e "Total Event Count for FIM Profile - $profile  is: \e[1;33m$total\e[0m"
                echo "----------------------------------------------------------"
        }

        #####################################################
        #Calling the function based on conditional statements
        #####################################################

        if [ -n "$event_count" ]
        then
                function_process
                echo "" >> finaloutput
        else
                echo -e "FIM Profile -\e[1;33m $profile\e[0m has \e[1;31m0 events\e[0m for given time range"
                echo "----------------------------------------------------------"
        fi
done < active_profiles

while read line
do
        rm -rf request.json > /dev/null
        ruleid=$(echo "$line" | awk -F'\t' '{print $2}')
        if [ -n "$dtrange" ]
        then
                rdtrange=$(echo " and $dtrange")
                echo "{" >> request.json
                echo "\"filter\":\"profile.rule.id:$ruleid$rdtrange\"," >> request.json
                echo "\"groupBy\":[\"action\"]" >> request.json
                echo "}" >> request.json
        else
                echo "{" >> request.json
                echo "\"filter\":\"profile.rule.id:$ruleid\"," >> request.json
                echo "\"groupBy\":[\"action\"]" >> request.json
                echo "}" >> request.json
        fi
        # action=$(curl -s -X POST https://gateway.$pod.apps.qualys.com/fim/v2/events/count -H "authorization: Bearer $token" -H 'content-type:application/json' -d @request.json)
        curl -s -k -X POST https://$pod/fim/v2/events/count -H "authorization: Bearer $token" -H 'content-type:application/json' -d @request.json > action
        raction=$(cat action | sed "s|\"||g;s/[{}]//g")
        echo -e "$line\t$raction" >> finaloutput
done < output

#cat finaloutput| grep -v "^$" | column -t -s $'\t' > Event_Analysis.csv
echo ""
cat finaloutput | sed 's|,| |g' | grep -v "^$" | sed 's|\t|,|g' > EventAnalysis

function_csv()
{
while read line
do
        Create=0
        Rename=0
        Delete=0
        Attributes=0
        Content=0
        Security=0
        for i in $(echo $line | cut -d ',' -f 5)
        do
                #echo $i
                sub=$(echo $i | cut -d ':' -f 1)
                eval ${sub}=$(echo $i | cut -d ':' -f 2)
                #echo ${!sub}
        done
        echo "$(echo $line | cut -d ',' -f 1,2,3,4),$Create,$Rename,$Delete,$Attributes,$Content,$Security">>csv
done < EventAnalysis
}

function_csv

cat csv | awk 'BEGIN{print "FIM Profile,RuleID,RuleName,EventCount,Create,Rename,Delete,Attributes,Content,Security"}1' > EventAnalysis.csv

echo -e "\e[1;31m----------------------------------------------------------\e[0m"
echo -e "The detailed output is saved in the file \e[1;33mEventAnalysis.csv\e[0m"
echo -e "\e[1;31m----------------------------------------------------------\e[0m"
echo -e ""
rm -rf EventAnalysis > /dev/null
rm -rf csv > /dev/null
