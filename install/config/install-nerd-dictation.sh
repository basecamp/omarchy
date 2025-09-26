# put nerd-dictation in ~/.config
# install nerd-dictation and download local translation model
git clone https://github.com/ideasman42/nerd-dictation.git ~/.config/nerd-dictation
wget https://alphacephei.com/kaldi/models/vosk-model-small-en-us-0.15.zip
mv vosk-model-small-en-us-0.15.zip ~/.config/nerd-dictation
unzip ~/.config/nerd-dictation/vosk-model-small-en-us-0.15.zip
mv ~/.config/nerd-dictation/vosk-model-small-en-us-0.15 ~/.config/nerd-dictation/model
