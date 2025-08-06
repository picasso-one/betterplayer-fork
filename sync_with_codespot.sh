
git fetch codespot
git update-ref refs/heads/develop codespot/develop
git pull codespot develop
if [ $? -eq 0 ]
then
    git push origin develop
fi

if [ $? -ne 0 ]
then
    set -a
    source sync.env
    set +a
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