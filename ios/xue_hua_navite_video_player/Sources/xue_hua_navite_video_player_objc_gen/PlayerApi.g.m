#include <stdint.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "xue_hua_navite_video_player.h"

#if !__has_feature(objc_arc)
#error "This file must be compiled with ARC enabled"
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct {
  int64_t version;
  void* (*newWaiter)(void);
  void (*awaitWaiter)(void*);
  void* (*currentIsolate)(void);
  void (*enterIsolate)(void*);
  void (*exitIsolate)(void);
  int64_t (*getMainPortId)(void);
  bool (*getCurrentThreadOwnsIsolate)(int64_t);
  void (*invokeListenerPortBlock)(int64_t port, void*);
  void (*invokeBlockingPortBlock)(int64_t port, void*, void*);
} DOBJC_Context;

id objc_retainBlock(id);

#define BLOCKING_BLOCK_IMPL(ctx, TYPE, SIG, INVOKE_DIRECT, INVOKE_LISTENER)    \
  assert(ctx->version >= 1);                                                   \
  void* targetIsolate = ctx->currentIsolate();                                 \
  int64_t targetPort = ctx->getMainPortId == NULL ? 0 : ctx->getMainPortId();  \
  __block __weak TYPE weakSelfBlock = nil;                                     \
  TYPE strongSelfBlock = [SIG {                                                \
    void* currentIsolate = ctx->currentIsolate();                              \
    bool mayEnterIsolate =                                                     \
        currentIsolate == NULL &&                                              \
        ctx->getCurrentThreadOwnsIsolate != NULL &&                            \
        ctx->getCurrentThreadOwnsIsolate(targetPort);                          \
    if (currentIsolate == targetIsolate || mayEnterIsolate) {                  \
      if (mayEnterIsolate) {                                                   \
        ctx->enterIsolate(targetIsolate);                                      \
      }                                                                        \
      INVOKE_DIRECT;                                                           \
      if (mayEnterIsolate) {                                                   \
        ctx->exitIsolate();                                                    \
      }                                                                        \
    } else {                                                                   \
      void* waiter = ctx->newWaiter();                                         \
      TYPE selfRetain = [weakSelfBlock copy];                                  \
      INVOKE_LISTENER;                                                         \
      ctx->awaitWaiter(waiter);                                                \
      (void)selfRetain;                                                        \
    }                                                                          \
  } copy];                                                                     \
  weakSelfBlock = strongSelfBlock;                                             \
  return strongSelfBlock;


__attribute__((visibility("default")))
@interface _13t6mte_BlockArgs_1pl9qdv : NSObject
@property (copy) id block;

@end
@implementation _13t6mte_BlockArgs_1pl9qdv
@end

typedef void  (^_ListenerTrampoline)(void);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline _13t6mte_wrapListenerBlock_1pl9qdv(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline weakSelfBlock = nil;
  _ListenerTrampoline strongSelfBlock = [^void() {
    @autoreleasepool {
      _13t6mte_BlockArgs_1pl9qdv* args = [[_13t6mte_BlockArgs_1pl9qdv alloc] init];
      args.block = weakSelfBlock;
      
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline)(void * waiter);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline _13t6mte_wrapBlockingBlock_1pl9qdv(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline, ^void(), {
    @autoreleasepool {
      _13t6mte_BlockArgs_1pl9qdv* args = [[_13t6mte_BlockArgs_1pl9qdv alloc] init];
      args.block = weakSelfBlock;
      
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _13t6mte_BlockArgs_1pl9qdv* args = [[_13t6mte_BlockArgs_1pl9qdv alloc] init];
      args.block = weakSelfBlock;
      
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _13t6mte_BlockArgs_xtuoz7 : NSObject
@property (copy) id block;
@property (strong) id arg0;
@end
@implementation _13t6mte_BlockArgs_xtuoz7
@end

typedef void  (^_ListenerTrampoline_1)(id arg0);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_1 _13t6mte_wrapListenerBlock_xtuoz7(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_1 weakSelfBlock = nil;
  _ListenerTrampoline_1 strongSelfBlock = [^void(id arg0) {
    @autoreleasepool {
      _13t6mte_BlockArgs_xtuoz7* args = [[_13t6mte_BlockArgs_xtuoz7 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_1)(void * waiter, id arg0);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_1 _13t6mte_wrapBlockingBlock_xtuoz7(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_1, ^void(id arg0), {
    @autoreleasepool {
      _13t6mte_BlockArgs_xtuoz7* args = [[_13t6mte_BlockArgs_xtuoz7 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _13t6mte_BlockArgs_xtuoz7* args = [[_13t6mte_BlockArgs_xtuoz7 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

__attribute__((visibility("default")))
@interface _13t6mte_BlockArgs_bklti2 : NSObject
@property (copy) id block;
@property void * arg0;
@property (strong) id arg1;
@property (strong) id arg2;
@property (copy) id arg3;
@end
@implementation _13t6mte_BlockArgs_bklti2
@end

typedef void  (^_ListenerTrampoline_2)(void * arg0, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_2 _13t6mte_wrapListenerBlock_bklti2(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_2 weakSelfBlock = nil;
  _ListenerTrampoline_2 strongSelfBlock = [^void(void * arg0, id arg1, id arg2, id arg3) {
    @autoreleasepool {
      _13t6mte_BlockArgs_bklti2* args = [[_13t6mte_BlockArgs_bklti2 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_2)(void * waiter, void * arg0, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_2 _13t6mte_wrapBlockingBlock_bklti2(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_2, ^void(void * arg0, id arg1, id arg2, id arg3), {
    @autoreleasepool {
      _13t6mte_BlockArgs_bklti2* args = [[_13t6mte_BlockArgs_bklti2 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _13t6mte_BlockArgs_bklti2* args = [[_13t6mte_BlockArgs_bklti2 alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline)(void * sel, id arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
void  _13t6mte_protocolTrampoline_bklti2(id target, void * sel, id arg1, id arg2, id arg3) {
  return ((_ProtocolTrampoline)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3);
}

__attribute__((visibility("default")))
@interface _13t6mte_BlockArgs_ymbgmo : NSObject
@property (copy) id block;
@property void * arg0;
@property BOOL arg1;
@property (strong) id arg2;
@property (copy) id arg3;
@end
@implementation _13t6mte_BlockArgs_ymbgmo
@end

typedef void  (^_ListenerTrampoline_3)(void * arg0, BOOL arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_3 _13t6mte_wrapListenerBlock_ymbgmo(
    int64_t port, DOBJC_Context* ctx) NS_RETURNS_RETAINED {
  __block __weak _ListenerTrampoline_3 weakSelfBlock = nil;
  _ListenerTrampoline_3 strongSelfBlock = [^void(void * arg0, BOOL arg1, id arg2, id arg3) {
    @autoreleasepool {
      _13t6mte_BlockArgs_ymbgmo* args = [[_13t6mte_BlockArgs_ymbgmo alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeListenerPortBlock(port, (__bridge_retained void*)args);
    }
  } copy];
  weakSelfBlock = strongSelfBlock;
  return strongSelfBlock;
}

typedef void  (^_BlockingTrampoline_3)(void * waiter, void * arg0, BOOL arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
_ListenerTrampoline_3 _13t6mte_wrapBlockingBlock_ymbgmo(int64_t port, DOBJC_Context* ctx,
    void (*directInvoke)(void*)) NS_RETURNS_RETAINED {
  BLOCKING_BLOCK_IMPL(ctx, _ListenerTrampoline_3, ^void(void * arg0, BOOL arg1, id arg2, id arg3), {
    @autoreleasepool {
      _13t6mte_BlockArgs_ymbgmo* args = [[_13t6mte_BlockArgs_ymbgmo alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      directInvoke((__bridge_retained void*)args);
    }
  }, {
    @autoreleasepool {
      _13t6mte_BlockArgs_ymbgmo* args = [[_13t6mte_BlockArgs_ymbgmo alloc] init];
      args.block = weakSelfBlock;
      args.arg0 = arg0;
      args.arg1 = arg1;
      args.arg2 = arg2;
      args.arg3 = arg3;
      ctx->invokeBlockingPortBlock(port, (__bridge_retained void*)args, waiter);
    }
  });
}

typedef void  (^_ProtocolTrampoline_1)(void * sel, BOOL arg1, id arg2, id arg3);
__attribute__((visibility("default"))) __attribute__((used))
void  _13t6mte_protocolTrampoline_ymbgmo(id target, void * sel, BOOL arg1, id arg2, id arg3) {
  return ((_ProtocolTrampoline_1)((id (*)(id, SEL, SEL))objc_msgSend)(target, @selector(getDOBJCDartProtocolMethodForSelector:), sel))(sel, arg1, arg2, arg3);
}

__attribute__((visibility("default"))) __attribute__((used))
Protocol* _13t6mte_PlayerFlutterApiBridge(void) { return @protocol(PlayerFlutterApiBridge); }
#undef BLOCKING_BLOCK_IMPL

#pragma clang diagnostic pop
