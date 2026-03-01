echo "Repair hibernation resume kernel parameters in Limine config"

MKINITCPIO_CONF="/etc/mkinitcpio.conf.d/omarchy_resume.conf"
NEEDS_REPAIR=0
RESUME_DEVICE=""
RESUME_OFFSET=""

if [[ ! -f $MKINITCPIO_CONF ]] || [[ ! -f /swap/swapfile ]]; then
  exit 0
fi

if [[ ! -x $OMARCHY_PATH/bin/omarchy-hibernation-setup ]]; then
  exit 0
fi

for token in $(cat /proc/cmdline); do
  if [[ $token == resume=* ]]; then
    RESUME_DEVICE=${token#resume=}
  fi

  if [[ $token == resume_offset=* ]]; then
    RESUME_OFFSET=${token#resume_offset=}
  fi
done

if [[ -z $RESUME_DEVICE ]] || [[ ! $RESUME_OFFSET =~ ^[0-9]+$ ]]; then
  NEEDS_REPAIR=1
fi

if [[ -f /etc/default/limine ]]; then
  if ! grep -Eq 'resume=[^" ]+' /etc/default/limine; then
    NEEDS_REPAIR=1
  fi

  if ! grep -Eq 'resume_offset=[0-9]+' /etc/default/limine; then
    NEEDS_REPAIR=1
  fi
fi

if [[ -f /etc/limine-entry-tool.d/resume.conf ]] && grep -Eq 'resume_offset=($|")' /etc/limine-entry-tool.d/resume.conf; then
  NEEDS_REPAIR=1
fi

if (( NEEDS_REPAIR )); then
  if ! "$OMARCHY_PATH/bin/omarchy-hibernation-setup" --force; then
    echo "Warning: automatic hibernation repair failed; run omarchy-hibernation-setup manually"
  fi
fi
