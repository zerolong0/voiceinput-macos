//
//  WhisperBridge.h
//  VoiceInput
//
//  Bridging header for whisper.cpp C library
//

#ifndef WhisperBridge_h
#define WhisperBridge_h

#import <Foundation/Foundation.h>

// Forward declarations
struct whisper_context;
struct whisper_context_params;
struct whisper_full_params;

typedef struct whisper_context whisper_context_t;
typedef struct whisper_context_params whisper_context_params_t;
typedef struct whisper_full_params whisper_full_params_t;

// Enum for sampling strategy
typedef enum whisper_sampling_strategy {
    WHISPER_SAMPLING_GREEDY = 0,
    WHISPER_SAMPLING_BEAM_SEARCH = 1
} whisper_sampling_strategy_t;

// Context functions
whisper_context_t * whisper_init_from_file(const char * path);
whisper_context_t * whisper_init_from_buffer(void * buffer, size_t buffer_size);
whisper_context_t * whisper_init_from_file_with_params(const char * path, whisper_context_params_t params);
void whisper_free(whisper_context_t * ctx);

// Context params
whisper_context_params_t whisper_context_default_params(void);

// Full params
whisper_full_params_t whisper_full_default_params(whisper_sampling_strategy_t strategy);

// Full transcription
int whisper_full(whisper_context_t * ctx, whisper_full_params_t params, const float * samples, int n_samples);
int whisper_full_n_segments(whisper_context_t * ctx);
const char * whisper_full_get_segment_text(whisper_context_t * ctx, int i_segment);
int64_t whisper_full_get_segment_t0(whisper_context_t * ctx, int i_segment);
int64_t whisper_full_get_segment_t1(whisper_context_t * ctx, int i_segment);
int whisper_full_get_segment_n_tokens(whisper_context_t * ctx, int i_segment);

// Language
const char * whisper_lang_str(int i);
int whisper_lang_id(const char * lang_str);

// Model info
int whisper_n_vocab(whisper_context_t * ctx);
int whisper_n_audio_ctx(whisper_context_t * ctx);
int whisper_n_audio_state(whisper_context_t * ctx);
int whisper_n_audio_head(whisper_context_t * ctx);
int whisper_n_audio_layer(whisper_context_t * ctx);
int whisper_n_text_ctx(whisper_context_t * ctx);
int whisper_n_text_state(whisper_context_t * ctx);
int whisper_n_text_head(whisper_context_t * ctx);
int whisper_n_text_layer(whisper_context_t * ctx);
int whisper_n_mels(whisper_context_t * ctx);
int whisper_n_threads(whisper_context_t * ctx);

// Full params setters
void whisper_full_params_set_language(whisper_full_params_t * params, const char * lang);
void whisper_full_params_set_n_threads(whisper_full_params_t * params, int n_threads);
void whisper_full_params_set_print_progress(whisper_full_params_t * params, bool print_progress);
void whisper_full_params_set_print_special(whisper_full_params_t * params, bool print_special);
void whisper_full_params_set_print_realtime(whisper_full_params_t * params, bool print_realtime);
void whisper_full_params_set_print_timestamps(whisper_full_params_t * params, bool print_timestamps);
void whisper_full_params_set_translate(whisper_full_params_t * params, bool translate);
void whisper_full_params_set_no_context(whisper_full_params_t * params, bool no_context);
void whisper_full_params_set_single_segment(whisper_full_params_t * params, bool single_segment);
void whisper_full_params_set_max_segment(whisper_full_params_t * params, int max_segment);

#endif /* WhisperBridge_h */
