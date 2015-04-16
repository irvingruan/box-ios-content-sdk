//
//  BOXFileThumbnailRequestTests.m
//  BoxContentSDK
//
//  Created by Rico Yao on 12/23/14.
//  Copyright (c) 2014 Box. All rights reserved.
//

#import "BOXRequestTestCase.h"
#import "BOXFileThumbnailRequest.h"
#import "BOXRequest_Private.h"

@interface BOXFileThumbnailRequestTests : BOXRequestTestCase
@end

@implementation BOXFileThumbnailRequestTests

#pragma mark - URL

- (void)test_that_thumbnail_request_has_expected_URLRequest
{
    NSString *fileID = @"123";
    BOXFileThumbnailRequest *request = [[BOXFileThumbnailRequest alloc] initWithFileID:fileID size:BOXThumbnailSize64];
    NSURLRequest *URLRequest = request.urlRequest;
    
    NSURL *expectedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/files/%@/thumbnail.png?max_width=%lu&max_height=%lu", BOXAPIBaseURL, BOXAPIVersion, fileID, (unsigned long)BOXThumbnailSize64, (unsigned long)BOXThumbnailSize64]];
    
    XCTAssertEqualObjects(expectedURL, URLRequest.URL);
    XCTAssertEqualObjects(@"GET", URLRequest.HTTPMethod);
}

- (void)test_shared_link_properties
{
    NSString *fileID = @"123";
    BOXFileThumbnailRequest *request = [[BOXFileThumbnailRequest alloc] initWithFileID:fileID size:BOXThumbnailSize64];
    
    XCTAssertEqualObjects([request itemIDForSharedLink], fileID);
    XCTAssertEqualObjects([request itemTypeForSharedLink], BOXAPIItemTypeFile);    
}

#pragma mark - Download data

- (void)test_that_thumbnail_request_returns_expected_thumbnail
{
    BOXFileThumbnailRequest *request = [[BOXFileThumbnailRequest alloc] initWithFileID:@"123" size:BOXThumbnailSize64];
    
    UIImage *cannedResponseImage = [self blankImageWithSize:CGSizeMake(128, 128) color:[UIColor greenColor]];
    NSData *cannedResponseData =  UIImagePNGRepresentation(cannedResponseImage);
    NSHTTPURLResponse *URLResponse = [self cannedURLResponseWithStatusCode:200 responseData:cannedResponseData];
    [self setCannedURLResponse:URLResponse cannedResponseData:cannedResponseData forRequest:request];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    [request performRequestWithProgress:nil completion:^(UIImage *image, NSError *error) {
        XCTAssertNil(error);
        // Difficult to test image equality but a size check if sufficient, and important to ensure
        // we respected screen scale (e.g. retina vs non-retina) when decoding.
        XCTAssertEqual(cannedResponseImage.size.width, image.size.width);
        XCTAssertEqual(cannedResponseImage.size.height, image.size.height);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)test_that_thumbnail_request_returns_expected_thumbnail_after_intermediate_202_responses
{
    BOXFileThumbnailRequest *request = [[BOXFileThumbnailRequest alloc] initWithFileID:@"123" size:BOXThumbnailSize64];
    
    UIImage *cannedResponseImage = [self blankImageWithSize:CGSizeMake(128, 128) color:[UIColor greenColor]];
    NSData *cannedResponseData =  UIImagePNGRepresentation(cannedResponseImage);
    NSHTTPURLResponse *URLResponse = [self cannedURLResponseWithStatusCode:200 responseData:cannedResponseData];
    BOXCannedResponse *cannedResponse = [[BOXCannedResponse alloc] initWithURLResponse:URLResponse responseData:cannedResponseData];
    
    // Simulate 3 intermediate 202 responses before we actually get the expected contents.
    NSInteger numberOfIntermediate202Responses = 3;
    cannedResponse.numberOfIntermediate202Responses = numberOfIntermediate202Responses;
    
    [self setCannedResponse:cannedResponse forRequest:request];
    
    // We expect the queueManager to re-enque after a 202 is received.
    __block NSInteger numberOfOperationsEnqueued = 0;
    id queueManagerMock = [OCMockObject partialMockForObject:request.queueManager];
    [[[[queueManagerMock stub] andDo:^(NSInvocation *invocation) {
        numberOfOperationsEnqueued++;
    }] andForwardToRealObject] enqueueOperation:OCMOCK_ANY];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    [request performRequestWithProgress:nil completion:^(UIImage *image, NSError *error) {
        XCTAssertNil(error);
        // Difficult to test image equality but a size check if sufficient, and important to ensure
        // we respected screen scale (e.g. retina vs non-retina) when decoding.
        XCTAssertEqual(cannedResponseImage.size.width, image.size.width);
        XCTAssertEqual(cannedResponseImage.size.height, image.size.height);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    
    // Expect 1 enqueueing for the initial request, and then 1 more for each of the intermediate 202 responses.
    XCTAssertEqual(1 + numberOfIntermediate202Responses, numberOfOperationsEnqueued);
}

#pragma mark - Progress blocks

- (void)test_that_thumbnail_request_calls_progress_blocks
{
    BOXFileThumbnailRequest *request = [[BOXFileThumbnailRequest alloc] initWithFileID:@"123" size:BOXThumbnailSize64];
    
    // Image has to be big enough to trigger chunking in BOXCannedURLProtocol
    UIImage *cannedResponseImage = [self blankImageWithSize:CGSizeMake(500, 500) color:[UIColor purpleColor]];
    NSData *cannedResponseData =  UIImagePNGRepresentation(cannedResponseImage);
    NSHTTPURLResponse *URLResponse = [self cannedURLResponseWithStatusCode:200 responseData:cannedResponseData];
    [self setCannedURLResponse:URLResponse cannedResponseData:cannedResponseData forRequest:request];
    
    __block long intermediateProgressBlockCalls = 0;
    __block long finalProgressBlockCalls = 0;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"expectation"];
    [request performRequestWithProgress:^(long long totalBytesTransferred, long long totalBytesExpectedToTransfer) {
        if (totalBytesTransferred < totalBytesExpectedToTransfer) {
            intermediateProgressBlockCalls++;
        }
        else if (totalBytesTransferred == totalBytesExpectedToTransfer) {
            finalProgressBlockCalls++;
        } else {
            XCTFail(@"Progress called with totalBytesTransferred greater than totalBytesExpectedToTransfer");
        }
        
    } completion:^(UIImage *image, NSError *error) {
        XCTAssertNotNil(image);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
    
    // Intermediate progress should be called at least once, and final should be called exactly once.
    XCTAssertGreaterThan(intermediateProgressBlockCalls,  0);
    XCTAssertEqual(1, finalProgressBlockCalls);
}

#pragma mark - Private helper

- (UIImage *)blankImageWithSize:(CGSize)size color:(UIColor *)color
{
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end