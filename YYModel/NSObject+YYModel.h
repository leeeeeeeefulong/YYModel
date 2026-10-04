//
//  NSObject+YYModel.h
//  YYModel <https://github.com/ibireme/YYModel>
//
//  Created by ibireme on 15/5/10.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//
//  Objective-C compatibility maintenance with documented fork extensions.
//  See docs/OBJC-MIGRATION.md for defaults and migration requirements.
//

#import <Foundation/Foundation.h>
#import "YYClassInfo.h"

NS_ASSUME_NONNULL_BEGIN

/**
 YYModel protocol for custom model transform.
 */
@protocol YYModel <NSObject>
@optional

/**
 Merge ancestor entries in modelCustomPropertyMapper and
 modelContainerPropertyGenericClass, from parent to child. Child entries win.
 The default is NO: only the most specific effective hook is called, as in
 original YYModel. Blacklist and whitelist hooks are never merged.
 This class policy is inherited and may be disabled by a subclass returning NO.
 */
+ (BOOL)modelMergesSuperclassConfiguration;

/**
 Custom property mapper.

 @return A map between property name and json key/keyPath.
 @code
 + (NSDictionary *)modelCustomPropertyMapper {
     return @{@"name" : @"n",
              @"page" : @"p",
              @"desc" : @"ext.desc",
              @"bookID" : @[@"id", @"book.ID", @"book_id"]};
 }
 */
+ (nullable NSDictionary<NSString *, id> *)modelCustomPropertyMapper;

/**
 Generic class container for array/dictionary properties.

 @return A map between property name and the class of items.
 @code
 + (NSDictionary *)modelContainerPropertyGenericClass {
     return @{@"users" : [User class],
              @"dict" : [NSDictionary class]};
 }
 */
+ (nullable NSDictionary<NSString *, id> *)modelContainerPropertyGenericClass;

/**
 If the default model-to-class transform is not what you want,
 implement this method to return a custom class.

 @param dictionary The json dictionary.
 @return A class, or nil to use the default.
 */
+ (nullable Class)modelCustomClassForDictionary:(NSDictionary *)dictionary;

/**
 Properties in the blacklist will be ignored in model-to-json and json-to-model.

 @return An array of property names.
 */
+ (nullable NSArray<NSString *> *)modelPropertyBlacklist;

/**
 Only properties in the whitelist will be involved in model-to-json and json-to-model.

 @return An array of property names.
 */
+ (nullable NSArray<NSString *> *)modelPropertyWhitelist;

/**
 Called before the json dictionary is set to the model.
 You can use this method to preprocess the dictionary.

 @param dictionary The original json dictionary.
 @return A processed dictionary, or nil to cancel the transform.
 */
- (nullable NSDictionary *)modelCustomWillTransformFromDictionary:(NSDictionary *)dictionary;

/**
 Called after the json dictionary is set to the model.
 You can use this method to do custom transform.

 @param dictionary The json dictionary.
 @return YES if transform succeed, NO to cancel.
 */
- (BOOL)modelCustomTransformFromDictionary:(NSDictionary *)dictionary;

/**
 Implement on the root model class to cancel a parse if any nested model dictionary
 transform fails. Strict nested conversions use the YYModel protocol hooks.
 The default is NO, preserving the original nested-model behavior. The policy is
 inherited by all dictionary conversions in this parse, including model containers.
 Already-instantiated model values are trusted. Updating an existing model can
 assign some properties before returning NO; this option does not provide rollback.
 */
+ (BOOL)modelRequiresSuccessfulNestedTransforms;

/**
 Called when the model is converted to a json dictionary.
 You can use this method to do custom transform.

 @param dictionary The mutable dictionary to be set.
 @return YES if transform succeed, NO to cancel.
 */
- (BOOL)modelCustomTransformToDictionary:(NSMutableDictionary *)dictionary;

@end


/**
 Provide methods to convert between json and model.
 */
@interface NSObject (YYModel)

///=============================================================================
/// @name Create Model from JSON
///=============================================================================

/**
 Creates and returns a model from a json string.
 Returns nil if an error occurs.

 @param json A json string, or a NSDictionary/NSArray.
 @return A new model, or nil if an error occurs.
 */
+ (nullable instancetype)yy_modelWithJSON:(id)json;

/**
 Creates and returns a model from a dictionary.
 Returns nil if an error occurs.

 @param dictionary A dictionary.
 @return A new model, or nil if an error occurs.
 */
+ (nullable instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary;

///=============================================================================
/// @name Set Model from JSON
///=============================================================================

/**
 Set the model with a json string.

 @param json A json string, or a NSDictionary/NSArray.
 @return YES if succeed, NO if an error occurs.
 */
- (BOOL)yy_modelSetWithJSON:(id)json;

/**
 Set the model with a dictionary.

 @param dictionary A dictionary.
 @return YES if succeed, NO if an error occurs.
 */
- (BOOL)yy_modelSetWithDictionary:(NSDictionary *)dictionary;

///=============================================================================
/// @name Model to JSON
///=============================================================================

/**
 Returns a json dictionary (NSMutableDictionary).
 Returns nil if an error occurs.
 */
- (nullable id)yy_modelToJSONObject;

/**
 Returns a json data (NSData).
 Returns nil if an error occurs.
 */
- (nullable NSData *)yy_modelToJSONData;

/**
 Returns a json string (NSString).
 Returns nil if an error occurs.
 */
- (nullable NSString *)yy_modelToJSONString;

///=============================================================================
/// @name Model Copy
///=============================================================================

/**
 Returns a copy of the model.
 Returns nil if an error occurs.
 */
- (nullable id)yy_modelCopy;

///=============================================================================
/// @name Coding (NSSecureCoding compatible)
///=============================================================================

/**
 Encode the model with a coder.
 Compatible with NSSecureCoding.
 */
- (void)yy_modelEncodeWithCoder:(NSCoder *)aCoder;

/**
 Initialize the model with a coder.
 Compatible with NSSecureCoding.
 */
- (nullable instancetype)yy_modelInitWithCoder:(NSCoder *)aCoder;

///=============================================================================
/// @name Hash & Equal
///=============================================================================

/**
 Returns the model's hash.
 */
- (NSUInteger)yy_modelHash;

/**
 Returns YES if the model is equal to another.
 */
- (BOOL)yy_modelIsEqual:(id)model;

/**
 Returns a human-readable description.
 */
- (NSString *)yy_modelDescription;

@end


/**
 Provide methods to convert between json and model array.
 */
@interface NSArray (YYModel)

/**
 Creates and returns an array from a json array.
 Returns nil if an error occurs.

 @param cls  The class of the model.
 @param json A json array (NSArray), or a json string.
 @return An array of model.
 */
+ (nullable NSArray *)yy_modelArrayWithClass:(Class)cls json:(id)json;

@end


/**
 Provide methods to convert between json and model dictionary.
 */
@interface NSDictionary (YYModel)

/**
 Creates and returns a dictionary from a json dictionary.
 Returns nil if an error occurs.

 @param cls  The class of the model.
 @param json A json dictionary (NSDictionary), or a json string.
 @return A dictionary of model.
 */
+ (nullable NSDictionary *)yy_modelDictionaryWithClass:(Class)cls json:(id)json;

@end

NS_ASSUME_NONNULL_END
