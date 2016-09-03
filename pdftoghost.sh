#!/usr/bin/env bash
#declare vars
filelist=/home/pi/PDFTOGHOST/filelist.txt
DLPATH=/home/pi/PDFTOGHOST/DLpdfs/
DLFILES=/home/pi/PDFTOGHOST/DLpdfs/*
SFPATH=/home/pi/PDFTOGHOST/SFpdfs/
SFFILES=/home/pi/PDFTOGHOST/SFpdfs/*
TEXTPATH=/home/pi/PDFTOGHOST/TXTpdfs/
TEXTFILES=/home/pi/PDFTOGHOST/TXTpdfs/*
HEADER=/home/pi/PDFTOGHOST/header.txt
ASSET=/assets/pdfs/
ASSETPATH=/var/www/ghost/content/themes/casper/assets/pdfs/
BlogAdress=""
GhostLogin=""
GhostPassword=""
ClientSecret=`curl $BlogAdress/ghost/signin/ | grep -o -P '(?<=env-clientSecret" content=").*(?=" data-type="string)'`
PostContent=""
Table="Table_"
BearerToken=""
Author=""
AutomaticMode="0"
Force="0"

###FUNCTIONS
#pre-script clean-up in case of failure
function cleanup
{
  rm $DLFILES
  rm $TEXTFILES
}

function setlogin
{
if [ "$AutomaticMode" = "0" ]; then
#prompt for user token
  echo "Hi there !"
  echo "You need to login for this to work"
  echo "Please type in your username"
  read GhostLogin
  echo "and now your password:"
  read GhostPassword
else
    echo "AutomaticMode is on, assuming variables are already set..."
fi
}

function init
{
#Login and get the BearerToken
  BearerToken=`curl --data grant_type=password --data username=$GhostLogin --data password=$GhostPassword --data client_id=ghost-admin --data client_secret=$ClientSecret $BlogAdress/ghost/api/v0.1/authentication/token | grep -o -P '(?<="access_token":").*(?=","refresh_token")'`
  Author=`curl --header "Authorization: Bearer $BearerToken" $BlogAdress/ghost/api/v0.1/users/me/ | grep -o -P '(?<="id":).*(?=,"uuid")'`
  # read -n1 -r -p "Logged in, got the bearer token ! Your Author id is $Author" key
}

function massdelete
{
  declare -a PostsToDelete=`curl --header "Authorization: Bearer $BearerToken" $BlogAdress/ghost/api/v0.1/posts/?limit=all\&filter=\(author_id:$Author\) | jq '.posts[] | .id'`
  echo "Posts to Delete ids: $PostsToDelete"
  for ThisPostId in $PostsToDelete
    do
    curl -X DELETE --header "Authorization: Bearer $BearerToken" $BlogAdress/ghost/api/v0.1/posts/$ThisPostId
  done
  echo "Deleted all the posts !" 
}

function getpdfs
{
#get all the pdfs locally
  while IFS= read -r line; do
    # echo "$line"
    # echo "$DLPATH$line"
    wget --directory-prefix=$DLPATH $line
  done < $filelist
  # read -n1 -r -p "All files have been successfuly downloaded !" key
#check if there are any updates, store in the PDF store if there are.
  for DLf in $DLFILES
    do
    filename=`echo "$DLf" | sed "s/.*\///"`
    #  echo "DLf concat: $SFPATH$filename"
    cmp --silent $DLf $SFPATH$filename && echo '### Files Are Identical! No action taken. ###' || mv $DLf $SFPATH
  done
  # read -n1 -r -p "All files have been checked and updated if necessary !" key
}

function prepposts
{
#main script routine
  for SFf in $SFFILES
    do
    filename=`echo "$SFf" | sed "s/.*\///"`
  #convert to text
    #  echo "SFf concat: $TEXTPATH$filename.txt"
    pdftotext -f 1 -l 15 $SFf $TEXTPATH$filename.txt
    noextfilename=`echo "$SFf" | sed "s/.*\///" | cut -f 1 -d '.'`
    Textf=$TEXTPATH$filename.txt
    TextTable=$TEXTPATH$Table$noextfilename.txt
    #  echo "$noextfilename"
    #  echo "$Textf"
    #  echo "$TextTable"
    #  read -n1 -r -p "Converted the file successfuly to PDF !" key
  #regex to get the table of contents
    pcregrep -i '^.*(\. \d).*$' $Textf > $TextTable
    #  read -n1 -r -p "Got the table of contents !" key
  #if no table of contents, push the 8 first pages.
    tablelinecount=$(wc -l < $TextTable)
    if (( $tablelinecount < 10 )); then
        #format the markdown content and add the download link
        sed -i 's/[[:punct:]]//g' $Textf && sed -i 's/[0-9]*//g' $Textf && sed -i 's/\s*$//g' $Textf && sed -i 's/\(^.*[A-Z]\b\)/###\1/' $Textf
        cat $HEADER $Textf | tr -cd '[:print:]\n' | sponge $Textf
        linkpath=$(echo $ASSET$noextfilename.pdf | sed 's_/_\\/_g')
        sed -i "s/replacethisdownloadlink/$linkpath/g" $Textf
        cp $Textf $TextTable
        # read -n1 -r -p "No Table of Contents found, Formatted original file !" key
      else
      #regex to succesively add some markdown, remove useless punctuation, digits and whitespace  
        sed -i 's/[[:punct:]]//g' $TextTable && sed -i 's/[0-9]*//g' $TextTable && sed -i 's/\s*$//g' $TextTable && sed -i 's/\(^.*[A-Z]\b\)/###\1/' $TextTable
      #add the header
        #  read -n1 -r -p "Formatted the file successfuly !" key
        cat $HEADER $TextTable | sponge $TextTable
        linkpath=$(echo $ASSET$noextfilename.pdf | sed 's_/_\\/_g')
        sed -i "s/replacethisdownloadlink/$linkpath/g" $TextTable
    #  read -n1 -r -p "Added the Download option and header !" key
        # read -n1 -r -p "Table of Contents ready for injection!" key
        echo "Table of Contents ready for injection!"
    fi
  #Prepare JSON. Some idiotic sed-ing takes place here to work around a limit concerning newlines : echo interprets them, curl doesn't like them, etc. So what we're doing is Sed-ing the post contents to replace newlines with br, storing that as a file, and then replacing those by \n to import. Works, but isn't pretty.
    PostContent=`sed -E ':a;N;$!ba;s/\r{0,1}\n/<br\/>/g' $TextTable`
    Slug=`echo "autopost-$noextfilename" | sed "s/ /-/g" | sed "s/_/-/g"`
    PostTitle=`echo "$noextfilename" | sed "s/-/ /g" | sed "s/_/ /g" | sed "s/\b\(.\)/\u\1/g"`
    JSON="{\"posts\":[{\"title\":\"$PostTitle\",\"slug\":\"$Slug\",\"markdown\":\"$PostContent\",\"image\":\"http://tolleson.com/wp-content/uploads/2015/06/salesforce-brand-logo-blue-on-gray.png\",\"featured\":false,\"page\":false,\"status\":\"draft\",\"language\":\"en_US\",\"meta_title\":null,\"meta_description\":null,\"author\":\"4\",\"publishedBy\":null,\"tags\":[{\"uuid\":\"ember2034\",\"name\":\"implementation guides\",\"slug\":null,\"description\":null,\"meta_title\":null,\"meta_description\":null,\"image\":null,\"visibility\":\"public\"}]}]}"
    echo $JSON > JSON.txt
    sed -i 's/<br\/>/\\n/g' JSON.txt
    #  read -n1 -r -p "READY ?!" key

  #Save the post as a draft
    curl --header "Authorization: Bearer $BearerToken" -H "Content-Type: application/json" -X POST -d @JSON.txt $BlogAdress/ghost/api/v0.1/posts
    #  read -n1 -r -p "Injected !" key
  done
}

function masspublish
{
  #Publish all the previously drafted posts
  declare -a PostsToPublish=`curl --header "Authorization: Bearer $BearerToken" $BlogAdress/ghost/api/v0.1/posts/?limit=all\&filter=\(status:draft\) | jq '.posts[] | .id'`
  echo "Posts to Publish ids: $PostsToPublish"
  for ThisPostId in $PostsToPublish
    do
    curl --header "Authorization: Bearer $BearerToken" -H "Content-Type: application/json" -X PUT -d '{"posts":[{"status":"published"}]}' $BlogAdress/ghost/api/v0.1/posts/$ThisPostId
  done
  echo "Published all drafts !"  
}

#move the PDFs to the assets folder for download
function allowdl
{
mv $SFFILES $ASSETPATH
}

function usage
{
    echo "usage: pdftoghost.sh [[-f] [-a (http://blog.mysite.eu ghostlogin ghostpassword customfilters)]] | [-h]]"
}

###ARGUMENTS
while [ "$1" != "" ]; do
    case $1 in
        -a | --automatic )      AutomaticMode=1
                                shift
                                BlogAdress=$1
                                GhostLogin=$2
                                GhostPassword=$3
                                CustomFilters=$4
                                cleanup
                                init
                                massdelete
                                getpdfs
                                prepposts
                                masspublish
                                allowdl
                                cleanup
                                exit
                                ;;
        -f | --force )          Force=1
                                ;;                                
        -h | --help )           usage
                                exit
                                ;;
        * )                     exit 1
    esac
    shift
done

###MAIN
cleanup
setlogin
init
massdelete
getpdfs
prepposts
masspublish
allowdl
cleanup
