/*
 _                        __                
| |___      _____        / _| __ _  ___ ___ 
| __\ \ /\ / / _ \ _____| |_ / _` |/ __/ _ \
| |_ \ V  V / (_) |_____|  _| (_| | (_|  __/
 \__| \_/\_/ \___/      |_|  \__,_|\___\___|
                                            

a schizoincestoid game pad instrument


TODO:
- Selectable sound sources
- Selectable fx patches (with Influx remapping)
- External control? IE. Sending data from these Influx to other things like the modular?
- Master fx (controlled by the compass?)
- Kinetic feedback via vibration?
- A way to switch everything into "persistence mode"
- 4 different kinds of patterns
- Connect patterns to controller/influx

*/

(
	~ff = ~ff ?? ();

	~ff.init = {|self|

		// Settings
		self.numTimeStretchers = 4;
		self.numVoiceChans = 2; 
		self.bufferDur = 16; 

		// Dependencies
		self.mktl = MKtl('gamepad1', "shanwan_ps3");
		self.sleet = self.sleet ?? Sleet.new(self.numVoiceChans);
		self.p = Particular.new(self.numVoiceChans);

		// The main buffer
		self.buffer = Buffer.alloc(s, s.sampleRate * self.bufferDur,  numChannels: self.numVoiceChans);

		// Map outputs of joystick to x/y of Influx
		self.mapToFlux.value;

		// Make the two voices
		self.setupVoices.value;

		// Add output processing to Influx
		self.makeEnvs.value;
		self.addProcessingToInfluxes.value;

		// Add named shortcuts for elements in the mktl
		self.renameElements.value;

		// Make time stretch patterns
		self.makePatterns.value;

		// Map using preset 1
		self.mappings['preset1'].keysValuesDo{|el, actionName|
			"Mapping % to %".format(el, actionName).postln;
			self.mktl.elAt(el).action = self.actions[actionName]
		};
	};


	~ff.ignoreParams = [
		\in,
		\vca,
		\record,
		\volume, \gain, \inGain, \ingain,
		\wet100, \wet101, \wet102, \wet103, \wet104 // vca, pan, volume, leakdc 
	];

	~ff.makePatterns = {|self|
		var pats = self.numTimeStretchers.collect{|stretchnum|
			var name = "twoface_ts%".format(stretchnum).asSymbol; 

			Pdef(name,
				Pbind(
					\instrument, self.p.def("hamm", "buf2"),
					\buffer, self.buffer,
					\timestretch, 3 * (stretchnum+1),
					\wobble, 0.5,
					\overlaps, 4, // Overlap between grains
					\bufdur, Pkey(\timestretch) * Pfunc({|ev| ev[\buffer].duration}),
					\start, Pwhite(0.99,1.0) * Pseg({[0, 1].scramble}, Pkey(\bufdur), \lin, inf), // Buffer pointer
					\freq, 0.70 * Pwhite(0.9,1.0), // Playback rate
					\dur, 0.001 + (stretchnum/100) * Pbrown(1,1+Pkey(\wobble), 0.001), // Duration of each sound event
					\sustain, Pkey(\overlaps) * Pkey(\dur),
					\amp, 0.125,
					\pan, Pkey(\start) // Pan follows buffer pointer
				)
			)
		};

		self.pats = pats;
	};

	// From alberto de campo's Influx examples
	~ff.fluxEnv = { |q, numSteps = 7, rand = 1.0, maxCurve = 3.0|
		var numTimes = numSteps.max(2).round(2).asInteger;
		var levels = (numTimes + 1).collect { |i| 1.0.rand2.blend( (i / numTimes).unibi, 1-rand) };
		// bit boring to have them regular
		var times = (1/numTimes).dup(numTimes);
		var curves = numTimes.collect { maxCurve.rand2 };
		// put in fixed values
		levels[0] = -1;
		levels[numTimes div: 2] = 0;
		levels[numTimes] = 1;
		Env(levels, times, curves);
	};

	~ff.makeEnvs = {|self|
		self.voices.do{|voice|
			var numouts = voice.influx.outNames.size;

			voice[\envs] = numouts.collect{ self.fluxEnv } 
		}
	};

	~ff.addProcessingToInfluxes = {|self|
		self.voices.do{|voice|
			voice.influx.addProc(\base, { |val, i|
				voice[\envs][i].at(val.tanh.biuni).biuni;
			})
		}
	};

	~ff.actions = {|self|

		(
			setfluxlx: {|el|
				var val = el.value.unibi; // Bipolar out for Influx 
				self.voices[\left].influx.set('x', val)
			},
			setfluxly: {|el|
				var val = el.value.unibi; // Bipolar out for Influx 
				self.voices[\left].influx.set('y', val)
			},
			setfluxrx: {|el|
				var val = el.value.unibi; // Bipolar out for Influx 
				self.voices[\right].influx.set('x', val)
			},
			setfluxry: {|el|
				var val = el.value.unibi; // Bipolar out for Influx 
				self.voices[\right].influx.set('y', val)
			},

			openVCAL: {|el| 
				self.voices[\left].ndef.set(\vca, el.value) 
			},
			openVCAR: {|el| 
				self.voices[\right].ndef.set(\vca, el.value) 
			},

			nextSoundL: {|el| 
				"Next sound for left voice".postln 
			},
			nextSoundR: {|el| 
				"Next sound for right voice".postln 
			},
			prevSoundL: {|el| },
			prevSoundR: {|el| },

			triggerRecL: {|el| self.voices[\left].ndef.set(\record, el.value)},
			triggerRecR: {|el| self.voices[\right].ndef.set(\record, el.value)},

			randWeightL: {|el| "Randomizing weights for left".postln; self.voices[\left].influx.rand },
			randWeightR: {|el| "Randomizing weights for right".postln; self.voices[\right].influx.rand },

			togglePat0: {|el| 
				var patnum=0;

				if(el.value == 1.0, { 

					if(self.pats[patnum].isPlaying,{
						"Stopping pat %".format(patnum).postln;
						self.pats[patnum].stop
					}, {
						"Playing pat %".format(patnum).postln;
						self.pats[patnum].play
					})

				})
			},
			togglePat1: {|el| 
				var patnum=1;

				if(el.value == 1.0, { 

					if(self.pats[patnum].isPlaying,{
						"Stopping pat %".format(patnum).postln;
						self.pats[patnum].stop
					}, {
						"Playing pat %".format(patnum).postln;
						self.pats[patnum].play
					})

				})
			},
			togglePat2: {|el| 
				var patnum=2;

				if(el.value == 1.0, { 

					if(self.pats[patnum].isPlaying,{
						"Stopping pat %".format(patnum).postln;
						self.pats[patnum].stop
					}, {
						"Playing pat %".format(patnum).postln;
						self.pats[patnum].play
					})

				})
			},
			togglePat3: {|el| 
				var patnum=3;

				if(el.value == 1.0, { 

					if(self.pats[patnum].isPlaying,{
						"Stopping pat %".format(patnum).postln;
						self.pats[patnum].stop
					}, {
						"Playing pat %".format(patnum).postln;
						self.pats[patnum].play
					})

				})
			},

		)
	};

	~ff.renameElements = {|self|

		// If PS3 controller
		if(self.mktl.device.name == 'hid_1_ps3_pc_wired_gamepad', {
			self.mktl.addNamed(\joyleftx, self.mktl.elAt('joy', 'l', 'x'));
			self.mktl.addNamed(\joylefty, self.mktl.elAt('joy', 'l', 'y'));
			self.mktl.addNamed(\joyrightx, self.mktl.elAt('joy', 'r', 'x'));
			self.mktl.addNamed(\joyrighty, self.mktl.elAt('joy', 'r', 'y'));

			self.mktl.addNamed(\a, self.mktl.elAt('bt', 'a'));
			self.mktl.addNamed(\b, self.mktl.elAt('bt', 'b'));
			self.mktl.addNamed(\x, self.mktl.elAt('bt', 'x'));
			self.mktl.addNamed(\y, self.mktl.elAt('bt', 'y'));

			self.mktl.addNamed(\lefthat, self.mktl.elAt('bt', 'hat_l'));
			self.mktl.addNamed(\righthat, self.mktl.elAt('bt', 'hat_r'));

			self.mktl.addNamed(\l1, self.mktl.elAt('bt', 'l1'));
			self.mktl.addNamed(\l2, self.mktl.elAt('bt', 'l2'));

			self.mktl.addNamed(\r1, self.mktl.elAt('bt', 'r1'));
			self.mktl.addNamed(\r2, self.mktl.elAt('bt', 'r2'));

			self.mktl.addNamed(\select, self.mktl.elAt('bt', 'sel'));
			self.mktl.addNamed(\start, self.mktl.elAt('bt', 'start'));

		});
	};

	~ff.mappings = (
		preset1: (
			\a: \togglePat0,
			\b: \togglePat1,
			\x: \togglePat2,
			\y: \togglePat3,

			\joyleftx: \setfluxlx,
			\joylefty: \setfluxly,

			\joyrightx: \setfluxrx,
			\joyrighty: \setfluxry,

			\lefthat: \nextSoundL,
			\righthat: \nextSoundR,

			\l1: \openVCAL,
			\r1: \openVCAR,

			\l2: \triggerRecL,
			\r2: \triggerRecR,

			\select: \randWeightL,
			\start: \randWeightR,
		)
	);

	~ff.setupVoices = {|self|

		// Setup voices
		self.voices = ();

		[\left, \right].do{|voxname|
			var ndefname = "twoface_%".format(voxname).asSymbol;
			var thisvoice;

			self.voices[voxname] = ();

			// Influx for this voice
			self.voices[voxname].influx = Influx.new(2, 128);

			// Setup the basic nodeproxy
			thisvoice = Ndef(ndefname).clear;
			thisvoice.play;
			thisvoice.mold(self.numVoiceChans, 'audio');

			thisvoice.source = self.soundProcesses[\sources][\default];

			// Add a few nice basic effects
			thisvoice[1] = \filter -> self.sleet.get('chorus');
			thisvoice[2] = \filter -> self.sleet.get('pitchshift');
			thisvoice[3] = \filter -> self.sleet.get('freqshift');
			thisvoice[4] = \filter -> self.sleet.get('delay');
			thisvoice[5] = \filter -> self.sleet.modules[\spectral].choose;
			thisvoice[6] = \filter -> self.sleet.get('octer');
			// thisvoice[7] = \filter -> self.sleet.get('waveloss');

			thisvoice[8] = \filter -> self.sleet.get('timemachine_ext');
			// thisvoice[5] = \filter -> self.sleet.get('scramble');
			// thisvoice[7] = \filter -> self.sleet.get('triode');
			// thisvoice[8] = \filter -> self.sleet.get('ring');

			// Plumming
			thisvoice[100] = \filter -> self.soundProcesses[\vca];
			thisvoice[101] = \filter -> self.soundProcesses[\pan];
			thisvoice[102] = \filter -> self.soundProcesses[\volume];
			thisvoice[103] = \filter -> self.soundProcesses[\leak];
			thisvoice[105] = \filter -> self.soundProcesses[\limiter];

			// Set default values
			thisvoice.set(
				\pan, 1.rand, 
				\buffer, self.buffer.bufnum,
				\record, 0
			);

			// Finally attach the voice to Influx
			self.voices[voxname].influx.attachMapped(
				thisvoice, 
				paramNames: thisvoice.controlKeys(except: self.ignoreParams)
			);

			self.voices[voxname].ndef = thisvoice;
		};

		// Attach voices to Influx
		// self.voices[]

	};

	~ff.soundProcesses = (
		/*

		Design principles for sound sources:

		- Make them stereo

		*/
		sources: (
			default: {|freq=444, detune=1, width=0.5, lfofreq=1, noise=0.5| 
				var sig = VarSaw.ar(
					freq: ([freq, freq-detune]*LFSaw.kr(freq/10*noise).linlin(-1.0,1.0,1.0,1.1)).wrap(50,1000), 
					iphase: 0, 
					width: width * LFSaw.kr(lfofreq*10).linlin(-1.0,1.0,0.0,1.0)
				);

				sig
			},
		),
		vca: {|in, vca=0, vcarelease=0.5| 
			in*EnvGen.kr(Env.asr(0.001,1.0,vcarelease), vca)
		},
		pan: {|in, pan=0| 
			Balance2.ar(in[0], in[1], pan.linlin(0.0,1.0,-1.0,1.0))
		},
		volume: {|in, volume=0.75|
			in * volume
		},
		leak: {|in|
			LeakDC.ar(in,  coef: 0.995,  mul: 1.0,  add: 0.0)
		},
		limiter: {|in|
			in.tanh
		}
	);

	s.waitForBoot{ ~ff.init.value };
)
