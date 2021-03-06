#import "ZMQSocket.h"
#import "ZMQContext.h"

enum {
	ZMQ_SOCKET_OPTION_MAX_LENGTH = 255,  // ZMQ_IDENTITY
};

@interface ZMQContext (ZMQSocketIsFriend)
@property(readonly) void *context;
@end

@interface ZMQSocket ()
@property(readwrite, getter=isClosed, NS_NONATOMIC_IPHONEONLY) BOOL closed;
@property(readonly) void *socket;
@end

static inline void ZMQLogError(id object, NSString *msg);

@implementation ZMQSocket
- (id)init {
	self = [super init];
	if (self) [self release];
	NSString *
	err = [NSString stringWithFormat:
	       @"%s: *** Create sockets using -[ZMQContext socketWithType:].",
	       __func__];
	NSLog(@"%@", err);
	@throw err;
	return nil;
}

- (id)initWithContext:(ZMQContext *)context_ type:(ZMQSocketType)type_ {
	self = [super init];
	if (!self) return nil;

	socket = zmq_socket(context_.context, type_);
	if (!socket) {
		ZMQLogError(self, @"zmq_socket");
		[self release];
		return nil;
	}

	context = context_;
	type = type_;
	return self;
}

@synthesize socket;
@synthesize closed;
- (void)close {
	int err = zmq_close(self.socket);
	if (err) {
		ZMQLogError(self, @"zmq_close");
		return;
	}
	self.closed = YES;
}

- (void)dealloc {
	[self close];
	[super dealloc];
}

@synthesize context;
@synthesize type;
- (NSString *)description {
	NSString *
	desc = [NSString stringWithFormat:@"<%@: %p (ctx=%p, type=%d, closed=%d)>",
	        [self class], self, self.context, (int)self.type, (int)self.closed];
	return desc;
}

#pragma mark Socket Options
- (BOOL)setData:(NSData *)data forOption:(ZMQSocketOption)option {
	int err = zmq_setsockopt(self.socket, option, [data bytes], [data length]);
	if (err) {
		ZMQLogError(self, @"zmq_setsockopt");
		return NO;
	}
	return YES;
}

- (NSData *)dataForOption:(ZMQSocketOption)option {
	size_t length = ZMQ_SOCKET_OPTION_MAX_LENGTH;
	void *storage = malloc(length);
	if (!storage) return nil;

	int err = zmq_getsockopt(self.socket, option, storage, &length);
	if (err) {
		ZMQLogError(self, @"zmq_getsockopt");
		free(storage);
		return nil;
	}

	NSData *
	data = [NSData dataWithBytesNoCopy:storage length:length freeWhenDone:YES];
	return data;
}

#pragma mark Endpoint Configuration
- (BOOL)bindToEndpoint:(NSString *)endpoint {
	const char *addr = [endpoint UTF8String];
	int err = zmq_bind(self.socket, addr);
	if (err) {
		ZMQLogError(self, @"zmq_bind");
		return NO;
	}
	return YES;
}

- (BOOL)connectToEndpoint:(NSString *)endpoint {
	const char *addr = [endpoint UTF8String];
	int err = zmq_connect(self.socket, addr);
	if (err) {
		ZMQLogError(self, @"zmq_connect");
		return NO;
	}
	return YES;	
}

#pragma mark Communication
- (BOOL)sendData:(NSData *)messageData withFlags:(ZMQMessageSendFlags)flags {
	zmq_msg_t msg;
	int err = zmq_msg_init_size(&msg, [messageData length]);
	if (err) {
		ZMQLogError(self, @"zmq_msg_init_size");
		return NO;
	}

	[messageData getBytes:zmq_msg_data(&msg) length:zmq_msg_size(&msg)];

	err = zmq_send(self.socket, &msg, flags);
	BOOL didSendData = (0 == err);
	if (!didSendData) {
		ZMQLogError(self, @"zmq_send");
		/* fall through */
	}

	err = zmq_msg_close(&msg);
	if (err) {
		ZMQLogError(self, @"zmq_msg_close");
		/* fall through */
	}
	return didSendData;
}

- (NSData *)receiveDataWithFlags:(ZMQMessageReceiveFlags)flags {
	zmq_msg_t msg;
	int err = zmq_msg_init(&msg);
	if (err) {
		ZMQLogError(self, @"zmq_msg_init");
		return nil;
	}

	err = zmq_recv(self.socket, &msg, flags);
	if (err) {
		ZMQLogError(self, @"zmq_recv");
		err = zmq_msg_close(&msg);
		if (err) {
			ZMQLogError(self, @"zmq_msg_close");			
		}
		return nil;
	}

	size_t length = zmq_msg_size(&msg);
	NSData *data = [NSData dataWithBytes:zmq_msg_data(&msg) length:length];

	err = zmq_msg_close(&msg);
	if (err) {
		ZMQLogError(self, @"zmq_msg_close");
		/* fall through */
	}
	return data;
}

#pragma mark Polling
- (void)getPollItem:(zmq_pollitem_t *)outItem forEvents:(short)events {
	NSParameterAssert(NULL != outItem);

	outItem->socket = self.socket;
	outItem->events = events;
	outItem->revents = 0;
}
@end

void
ZMQLogError(id object, NSString *msg) {
	NSLog(@"%s: *** %@: %@: %s",
	      __func__, object, msg, zmq_strerror(zmq_errno()));
}
