//
//  RACSequence.m
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2012-10-29.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACSequence.h"
#import "RACArraySequence.h"
#import "RACDynamicSequence.h"
#import "RACEmptySequence.h"

@implementation RACSequence

#pragma mark Lifecycle

+ (RACSequence *)emptySequence {
	return RACEmptySequence.emptySequence;
}

+ (RACSequence *)sequenceWithObject:(id)obj {
	return [RACDynamicSequence sequenceWithHeadBlock:^{
		return obj;
	} tailBlock:nil];
}

+ (RACSequence *)sequenceWithConcatenatedSequences:(NSArray *)seqs {
	return [RACArraySequence sequenceWithArray:seqs offset:0].flattenedSequence;
}

#pragma mark Class cluster primitives

- (id)head {
	NSAssert(NO, @"%s must be overridden by subclasses", __func__);
	return nil;
}

- (RACSequence *)tail {
	NSAssert(NO, @"%s must be overridden by subclasses", __func__);
	return nil;
}

#pragma mark Extended methods

- (NSArray *)array {
	NSMutableArray *array = [NSMutableArray array];
	for (id obj in self) {
		[array addObject:obj];
	}

	return [array copy];
}

- (RACSequence *)drop:(NSUInteger)count {
	RACSequence *seq = self;
	for (NSUInteger i = 0; i < count; i++) {
		seq = seq.tail;
	}

	return seq;
}

- (RACSequence *)sequenceByPrependingObject:(id)obj {
	NSParameterAssert(obj != nil);

	return [RACDynamicSequence sequenceWithHeadBlock:^{
		return obj;
	} tailBlock:^{
		return self;
	}];
}

- (RACSequence *)flattenedSequence {
	__block RACSequence *(^nextSequence)(RACSequence *, RACSequence *);
	
	nextSequence = [^ RACSequence * (RACSequence *current, RACSequence *remainingSeqs) {
		if (current == nil) {
			// We've exhausted one sequence, try the next.
			current = remainingSeqs.head;

			if (current == nil) {
				// We've exhausted all the sequences.
				return nil;
			}

			remainingSeqs = remainingSeqs.tail;
		}

		NSAssert([current isKindOfClass:RACSequence.class], @"Sequence being flattened contains an object that is not a sequence: %@", current);

		return [RACDynamicSequence sequenceWithHeadBlock:^{
			return current.head;
		} tailBlock:^{
			return nextSequence(current.tail, remainingSeqs);
		}];
	} copy];

	return nextSequence(self.head, self.tail);
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
	return self;
}

#pragma mark NSCoding

- (Class)classForCoder {
	// All sequences should be archived as RACArraySequences.
	return RACArraySequence.class;
}

- (id)initWithCoder:(NSCoder *)coder {
	if (![self isKindOfClass:RACArraySequence.class]) return [[RACArraySequence alloc] initWithCoder:coder];

	// Decoding is handled in RACArraySequence.
	return [super init];
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeObject:self.array forKey:@"array"];
}

#pragma mark NSFastEnumeration

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id *)stackbuf count:(NSUInteger)len {
	if (state->state == 0) {
		// Since a sequence doesn't mutate, this just needs to be set to
		// something non-NULL.
		state->mutationsPtr = state->extra;
	}

	state->itemsPtr = stackbuf;

	RACSequence *seq = self;
	NSUInteger enumeratedCount = 0;

	while (enumeratedCount < len) {
		// Because the objects in a sequence may be generated lazily, we want to
		// prevent them from being released until the enumerator's used them.
		__autoreleasing id obj = seq.head;
		if (obj == nil) break;

		stackbuf[enumeratedCount++] = obj;
		seq = seq.tail;
	}

	return enumeratedCount;
}

#pragma mark NSObject

- (NSUInteger)hash {
	return [self.head hash];
}

- (BOOL)isEqual:(RACSequence *)seq {
	if (self == seq) return YES;
	if (![seq isKindOfClass:RACSequence.class]) return NO;

	for (id<NSObject> selfObj in self) {
		id<NSObject> seqObj = seq.head;

		// Handles the nil case too.
		if (![seqObj isEqual:selfObj]) return NO;
	}

	// self is now depleted -- the argument should be too.
	return (seq.head == nil);
}

@end
