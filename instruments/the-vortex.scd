/*

 _   _                            _            
| |_| |__   ___  __   _____  _ __| |_ _____  __
| __| '_ \ / _ \ \ \ / / _ \| '__| __/ _ \ \/ /
| |_| | | |  __/  \ V / (_) | |  | ||  __/>  < 
 \__|_| |_|\___|   \_/ \___/|_|   \__\___/_/\_\
                                               
A cybernetic polyvoice reel to reel emulator matrix mixer / feedback system / looping delay

Dependencies:
- Sleet
- Modality
- Influx

Specs: 
- one sound input (from a modular synth or mic for example)
- sound going into 8 voices
- The input of each voice is a feedback matrix mixer with the input and all voices' outputs
- each voice has a time machine buffer looper/recorder at the end of an fx chain 

TODO:
- GUI
- rewrite to not conflict with other q objects
- Switchable input / input mixer

*/
(
	q = q ?? ();

	q.numVoices = 8;
	q.numOutputChans = 2;
	q.controllerChoice = "korg-nanokontrol2";

	q.init = {|self|

		fork{

			// FX system
			self.sleet = Sleet.new(self.numOutputChans);
			s.sync;

			// Set up voices' sound sources
			self.makeVoices.value;
			s.sync;

			// Make mixers - each voice get's a "mix" parameter per mix in voice (using nodeproxy roles)
			self.makeMixers.value;
			s.sync;

			// self.modality = self.modality ?? MKtl('cyber1', self.controllerChoice);

			self.setupController.value;
			s.sync;

			self.addTimemachine.value;
			s.sync;

			self.addFx.value;
			s.sync;

		}
	};

	// TODO
	q.setupController = {|self|};

	q.addFx = {|self|
		var baseIndex = self.numVoices;

		self.voices.do{|thisvoice|

			// thisvoice[baseIndex+1] = \kfilter -> self.sleet.get('smear');
			thisvoice[baseIndex+2] = \kfilter -> self.sleet.get('pitchshift');
			thisvoice[baseIndex+3] = \kfilter -> self.sleet.get('freqshift');
			thisvoice[baseIndex+4] = \kfilter -> self.sleet.get('delay');
			thisvoice[baseIndex+5] = \kfilter -> self.sleet.get('chorus');
			thisvoice[baseIndex+6] = \kfilter -> self.sleet.get('filter');

			thisvoice[1002] = \filterIn -> {|in| LeakDC.ar(in).tanh};
		}
	};

	q.addTimemachine = {|self|
		self.voices.do{|thisvoice|
			thisvoice[1001] = \filter -> self.sleet.get('timemachine');

			thisvoice.set(\timerate, rrand(0.0,1.0));
		}
	};

	q.makeVoices = {|self|
		self.voices = self.numVoices.collect{|voxnum| 
			var voicename = "voice%".format(voxnum).asSymbol;

			// Define the source of the voice
			Ndef(voicename).source = {|in=#[ 0, 1 ], inVol=0.4|
			SoundIn.ar(in, inVol)
			// SinOsc.ar(110 * (voxnum+1))!2 * inVol
		};

		// Make sure voice is audio and the right amount of channels
		Ndef(voicename).mold(self.numOutputChans, 'audio').play;

	}
};

q.makeMixers = {|self|

	self.numVoices.do{|voxnum|

		// Mix in all other voices (rejecting this one)
		(0..self.numVoices-1).reject({|i| i == voxnum}).do{|otherVoxNum, index|
			var thisVoice = "voice%".format(voxnum).asSymbol;
			var mixinVoice = "voice%".format(otherVoxNum).asSymbol;

			index = index + 1; // Start from 1 to not overwrite source

			Ndef(thisVoice)[index] = \mix -> { Ndef(mixinVoice).ar };

			// Set mix in parameter to 0 by default 
			Ndef(thisVoice).set("mix%".format(index).asSymbol, rrand(0.0,0.5))
		};
	}
};

q.init.value

)
(
	Ndef(\hej, {SinOsc.ar(110)*0.25});
	Ndef(\matrixMixer, {|...args| Splay.ar(args)}).map(\hejhej, Ndef(\hej)).mold(2, 'audio').play
)

Ndef(\voice0)[2] = \mix -> {Ndef(\yo)}

Ndef(\voice6).play
Ndef(\voice2).play

Ndef(\voice6).gui
Ndef(\voice6).scope
Ndef(\voice2).gui


MKtl.new('l', "korg-nanokontrol2")
MKtl('l').gui


Ndef("yo", { SoundIn.ar(0).poll })

s.record

z.list
z = Sleet.new
z.postInfo

q.voices.do{|voice| 
	var params = voice.controlKeys.reject({|key| key == 'in'});

	params.do{|paramname|
		voice.set(paramname,rrand(0.0,1.0))
	};

}
