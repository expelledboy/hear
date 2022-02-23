/*
    hear - Command line speech recognition for macOS

    Copyright (c) 2022 Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification,
    are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice, this
    list of conditions and the following disclaimer in the documentation and/or other
    materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its contributors may
    be used to endorse or promote products derived from this software without specific
    prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
    INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

#import <Speech/Speech.h>
#import "Hear.h"

@interface Hear()

@property (nonatomic, retain) AVAudioEngine *engine;
@property (nonatomic, retain) SFSpeechRecognizer *recognizer;
@property (nonatomic, retain) SFSpeechAudioBufferRecognitionRequest *request;
@property (nonatomic, retain) SFSpeechRecognitionTask *task;
@property (nonatomic, retain) NSString *language;
@property (nonatomic, retain) NSString *inputFile;
@property (nonatomic, retain) NSString *inputFormat;
@property (nonatomic) BOOL useOnDeviceRecognition;

@end

@implementation Hear

+ (NSArray<NSString *> *)supportedLanguages {
    NSMutableArray *localeIdentifiers = [NSMutableArray new];
    for (NSLocale *locale in [SFSpeechRecognizer supportedLocales]) {
        [localeIdentifiers addObject:[locale localeIdentifier]];
    }
    [localeIdentifiers sortUsingSelector:@selector(compare:)];
    return [localeIdentifiers copy];
}

+ (void)printSupportedLanguages {
    NSArray *localeIdentifiers = [Hear supportedLanguages];
    for (NSString *identifier in localeIdentifiers) {
        NSPrint(identifier);
    }
}

- (instancetype)initWithLanguage:(NSString *)language
                           input:(NSString *)input
                          format:(NSString *)fmt
                        onDevice:(BOOL)onDevice {
    if ((self = [super init])) {
        self.language = language;
        self.inputFile = input;
        self.inputFormat = fmt;
        self.useOnDeviceRecognition = onDevice;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self requestSpeechRecognitionPermission];
}

- (void)requestSpeechRecognitionPermission {
    
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus authStatus) {
        switch (authStatus) {
            
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                //User gave access to speech recognition
                DLog(@"Authorized");
                [self startListening];
                break;
                
            case SFSpeechRecognizerAuthorizationStatusDenied:
                // User denied access to speech recognition
                NSPrintErr(@"Speech recognition authorization denied");
                break;
                
            case SFSpeechRecognizerAuthorizationStatusRestricted:
                // Speech recognition restricted on this device
                NSPrintErr(@"Speech recognition authorization restricted on this device");
                break;
                
            case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                // Speech recognition not yet authorized
                NSPrintErr(@"Speech recognition authorization not yet authorized");
                break;
                
            default:
                break;
        }
    }];
}

- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task
         didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult {
    NSString *recognizedText = recognitionResult.bestTranscription.formattedString;
    NSPrint(@"%@", recognizedText);
}

- (void)startListening {
    
    // Create speech recognition request
    self.request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    if (self.request == nil) {
        NSPrintErr(@"Unable to initialize speech recognition request");
        return;
    }
    
    // Initialize speech recognizer
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en-US"];
    self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    self.recognizer.delegate = self;
    if (self.recognizer == nil) {
        NSPrintErr(@"Unable to initialize speech recognizer");
        exit(EXIT_FAILURE);
    }
    
    // Make sure recognition is available
    if (self.recognizer.isAvailable == NO) {
        NSPrintErr(@"Speech recognizer not available");
        exit(EXIT_FAILURE);
    }
    
    if (self.useOnDeviceRecognition && !self.recognizer.supportsOnDeviceRecognition) {
        NSPrintErr(@"On-device recognition is not supported for %@", self.language);
        exit(EXIT_FAILURE);
    }
    
    if (self.recognizer.supportsOnDeviceRecognition) {
        DLog(@"Speech recognizer supports on-device recognition");
        self.request.requiresOnDeviceRecognition = YES;
    }
    
    self.request.shouldReportPartialResults = YES;
    self.request.requiresOnDeviceRecognition = self.useOnDeviceRecognition;
    
//    self.task = [self.recognizer recognitionTaskWithRequest:self.request
//                                                   delegate:self];
    
    self.task = [self.recognizer recognitionTaskWithRequest:self.request
                                              resultHandler:
    ^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        BOOL isFinal = result.isFinal;
        if (isFinal) {
            DLog(@"Final result");
        }
        if (error != nil) {
            DLog(@"Error: %@", error.localizedDescription);
            return;
        }
        NSString *s = result.bestTranscription.formattedString;
        NSPrint(s);
    }];
    
    if (self.task == nil) {
        NSPrintErr(@"Unable to initialize speech recognition task");
        return;
    }
    
    DLog(@"Creating engine");
    self.engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = self.engine.inputNode;
    
    id recFmt = [inputNode outputFormatForBus:0];
        
    [inputNode installTapOnBus:0
                    bufferSize:1024
                        format:recFmt
                         block:
     ^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [self.request appendAudioPCMBuffer:buffer];
    }];
    
    NSError *err;
    DLog(@"Starting engine");
    [self.engine prepare];
    [self.engine startAndReturnError:&err];
    if (err != nil) {
        NSPrintErr(@"Error: %@", [err localizedDescription]);
        exit(EXIT_FAILURE);
    }
}

@end
