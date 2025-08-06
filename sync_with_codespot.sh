
git fetch codespot develop
CODESPOT_HASH=$(git rev-parse codespot/develop)
ORIGIN_HASH=$(git rev-parse develop)
if [ "$CODESPOT_HASH" != "$ORIGIN_HASH" ]
then
    set -a
    source sync.env
    set +a
    git update-ref refs/heads/develop codespot/develop
    git push origin develop
    if [ $? -ne 0 ]
    then
        SUBJECT="$SUBJECT_NEGATIVE"
    else
        SUBJECT="$SUBJECT_POSITIVE"
    fi
    sendemail \
        -f "$FROM_EMAIL" \
        -t "$TO_EMAIL" \
        -u "$SUBJECT" \
        -m "$BODY" \
        -s "$SMTP_SERVER:$SMTP_PORT" \
        -xu "$SMTP_USER" \
        -xp "$SMTP_PASS" \
        -o tls=yes
fi