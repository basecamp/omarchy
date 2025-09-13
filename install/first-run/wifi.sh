if ! ping -c5 -W1 1.1.1.1 >/dev/null 2>&1; then
  setsid $TERMINAL --class=Impala -e impala &
fi
