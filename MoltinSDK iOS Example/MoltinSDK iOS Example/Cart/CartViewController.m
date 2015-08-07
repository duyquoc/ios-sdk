//
//  CartViewController.m
//  MoltinSDK iOS Example
//
//  Created by Moltin on 19/06/15.
//  Copyright (c) 2015 Moltin. All rights reserved.
//

#import "CartViewController.h"
#import "AddressEntryViewController.h"
#import "CartListCell.h"

static NSString *CartCellIdentifier = @"MoltinCartCell";
static NSInteger ApplePaySheetId = 100;

// The maximum amount an Apple Pay transaction can be in the store's currency
// (for example, in the UK this is £20.00, so the value is 20.00)
static double ApplePayMaximumLimit = 20.00;

// The following constant is your Apple Pay merchant ID, as registered in the Apple Developer site
// You must also create a certificate for this merchant ID, as per the Stripe guide at https://stripe.com/docs/mobile/apple-pay
static NSString *ApplePayMerchantId = @"merchant.com.moltin.ApplePayExampleApp";

// The following constant is your Stripe Publishable API key - this must be the publishable key that corresponds to the secret key that you use for your Stripe payment gateway on your Moltin store.
// This needs to be here for Apple Pay Purposes
static NSString *StripePublishableKey = @"";

// The Stripe payment gateway must be enabled on your Moltin store to use Apple Pay
static NSString *ApplePayPaymentGateway = @"stripe";

static NSString *PAYMENT_METHOD  = @"purchase";

@interface CartViewController ()

@property (strong, nonatomic) NSNumber *cartPrice;
@property (strong, nonatomic) NSNumber *discountAmount;
@property (strong, nonatomic) NSDictionary *cartData;
@property (strong, nonatomic) NSArray *shippingMethods;
@property (strong, nonatomic) NSArray *countries;

@end

@implementation CartViewController

+ (CartViewController *)sharedInstance {
    static CartViewController *_sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedClient = [[CartViewController alloc] init];
    });
    
    return _sharedClient;
}

- (id)init{
    self = [super initWithNibName:@"CartView" bundle:nil];
    if (self) {
        
    }
    return self;
}


- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadCart) name:kMoltinNotificationRefreshCart object:nil];
    
    self.view.backgroundColor = MOLTIN_DARK_BACKGROUND_COLOR;
    [self.tableView registerNib:[UINib nibWithNibName:@"CartListCell" bundle:nil] forCellReuseIdentifier:CartCellIdentifier];
    
    self.tableView.allowsMultipleSelectionDuringEditing = NO;
    
    
    // Initialise the Stripe SDK with our API key, for Apple Pay purposes
    [Stripe setDefaultPublishableKey:StripePublishableKey];
    
    // get countries too.
    
    [[Moltin sharedInstance].address fieldsWithCustomerId:@""
                                             andAddressId:@""
                                                  success:^(NSDictionary *response) {
         NSDictionary *tmpCountries = [response valueForKeyPath:@"result.country.available"];
         
         NSMutableArray *tmp = [NSMutableArray array];
         for (NSString *countryCode in [tmpCountries allKeys]) {
             [tmp addObject:@{@"code":countryCode,@"name":[tmpCountries valueForKey:countryCode]}];
         }
         
         NSSortDescriptor *sortByName = [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                                      ascending:YES];
         self.countries = [tmp sortedArrayUsingDescriptors:@[sortByName]];
         
     } failure:^(NSDictionary *response, NSError *error) {
         ALERT(@"Sorry, we can't load countries at this time", @"Checkout is unavalabile without countries loaded");
         NSLog(@"ERROR fetching country list: %@", response);
     }];

    
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self loadCart];
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMoltinNotificationRefreshCart object:nil];
}

- (void)loadCart{
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.labelText = @"Loading Cart";
    
    __weak CartViewController *weakSelf = self;
    [[Moltin sharedInstance].cart getContentsWithsuccess:^(NSDictionary *response) {
        _cartData = response;
        [weakSelf parseCartItems];
        
        weakSelf.cartPrice = [_cartData valueForKeyPath:@"result.totals.post_discount.raw.with_tax"];
        weakSelf.lbTotalPrice.text = [_cartData valueForKeyPath:@"result.totals.post_discount.formatted.with_tax"];
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    } failure:^(NSDictionary *response, NSError *error) {
        NSLog(@"CART ERROR: %@\nWITH RESPONSE: %@", error, response);
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    }];
}

- (void)parseCartItems
{
    NSDictionary *tmpCartItems = [self.cartData valueForKeyPath:@"result.contents"];
    if (tmpCartItems.count > 0) {
        self.cartItems = [tmpCartItems objectsForKeys:[tmpCartItems allKeys] notFoundMarker:[NSNull null]];
        self.lbNoProductsInCart.hidden = YES;
    }
    else{
        self.cartItems = nil;
        self.lbNoProductsInCart.hidden = NO;
    }
    
    self.btnCheckout.enabled = self.lbNoProductsInCart.hidden;
    [self.tableView reloadData];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)canUseApplePayForCart {
    // to use Apple Pay, the cart value must be under the limit, and the user must have an Apple Pay capable device.
    BOOL withinLimit = (self.cartPrice.doubleValue < ApplePayMaximumLimit && self.cartPrice.doubleValue > 0);
    BOOL supportedDevice = [PKPaymentAuthorizationViewController canMakePayments];
    
    if (supportedDevice && withinLimit) {
        // then yes.
        return YES;
    }
    
    return NO;
}

- (IBAction)btnCheckoutTap:(id)sender {
    // see if they can use Apple Pay - if so, present the Apple Pay option, if not, don't.
    if ([self canUseApplePayForCart]) {
        // present payment method choice sheet
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"Select Payment Method"
                                                                 delegate:self
                                                        cancelButtonTitle:nil
                                                   destructiveButtonTitle:nil
                                                        otherButtonTitles:@"Apple Pay", @"Credit/Debit Card", nil];
        actionSheet.tag = ApplePaySheetId;
        [actionSheet showInView:self.view];
        
    } else {
        // fallback to standard checkout flow
        [self presentStandardCheckoutFlow];
    }
    
}

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex{
    if (buttonIndex == 0) {
        // Apple Pay
        [self checkoutWithApplePay];
    } else {
        // Normal checkout flow
        [self presentStandardCheckoutFlow];
    }
}

- (void)presentStandardCheckoutFlow {
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"CheckoutStoryboard" bundle:nil];
    UIViewController *vc = [sb instantiateInitialViewController];
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    
    [[MTSlideNavigationController sharedInstance] presentViewController:vc animated:YES completion:nil];
}

- (void)checkoutWithApplePay {
    // first, get shipping methods - then show the Apple pay view controller
    
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.labelText = @"Loading Shipping Methods";
    
    [[Moltin sharedInstance].cart checkoutWithsuccess:^(NSDictionary *response) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        
        self.shippingMethods = [response valueForKeyPath:@"result.shipping.methods"];
        [self showApplePayViewController];
    } failure:^(NSDictionary *response, NSError *error) {
        NSLog(@"SHIPPING ERROR: %@", error);
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    }];
    
    
}

- (void)showApplePayViewController {
    PKPaymentRequest *request = [[PKPaymentRequest alloc] init];
    
    // IMPORTANT: Change this to your own merchant ID at the start of this file
    request.merchantIdentifier = ApplePayMerchantId;
    
    // Stripe supports all 3 Apply Pay networks
    request.supportedNetworks = @[PKPaymentNetworkAmex, PKPaymentNetworkMasterCard, PKPaymentNetworkVisa];
    request.merchantCapabilities = PKMerchantCapability3DS;
    
    // The example store is in the GB region, with pricing in GBP
    request.countryCode = @"GB";
    request.currencyCode = @"GBP";
    
    request.requiredBillingAddressFields = PKAddressFieldAll;
    request.requiredShippingAddressFields = PKAddressFieldAll;
    
    
    // Payment summary items must contain a total, any discount, and then the company name being paid
    
    NSDecimalNumber *subtotalAmount = [NSDecimalNumber decimalNumberWithDecimal:[self.cartPrice decimalValue]];
    PKPaymentSummaryItem *subtotal = [PKPaymentSummaryItem summaryItemWithLabel:@"Subtotal" amount:subtotalAmount];
    
    NSDecimalNumber *totalAmount = [NSDecimalNumber zero];
    totalAmount = [totalAmount decimalNumberByAdding:subtotalAmount];
    PKPaymentSummaryItem *total = [PKPaymentSummaryItem summaryItemWithLabel:@"Moltin" amount:totalAmount];
    
    request.paymentSummaryItems =  @[subtotal, total];
    
    // Now set up shipping methods too...
    NSMutableArray *shippingMethods = [NSMutableArray array];
    
    for (NSDictionary *method in self.shippingMethods) {
        NSDecimalNumber *shippingCost = [NSDecimalNumber decimalNumberWithDecimal:[[method valueForKeyPath:@"price.data.raw.with_tax"] decimalValue]];
        PKShippingMethod *shippingMethod = [PKShippingMethod summaryItemWithLabel:[method objectForKey:@"title"] amount:shippingCost];
        shippingMethod.detail = [method objectForKey:@"company"];
        shippingMethod.identifier = [method valueForKey:@"slug"];
        
        [shippingMethods addObject:shippingMethod];
        
        
    }
    
    request.shippingMethods = [NSArray arrayWithArray:shippingMethods];
    
    PKPaymentAuthorizationViewController *applePayViewController = [[PKPaymentAuthorizationViewController alloc] initWithPaymentRequest:request];
    
    applePayViewController.delegate = self;
    
    [self presentViewController:applePayViewController animated:YES completion:nil];
    
}

#pragma mark - Apple Pay Delegate methods

- (void)paymentAuthorizationViewController:(PKPaymentAuthorizationViewController *)controller didAuthorizePayment:(PKPayment *)payment completion:(void (^)(PKPaymentAuthorizationStatus))completion {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    
    NSDictionary *billingAddressDict = nil;
    if (payment.billingAddress) {
        billingAddressDict = [self createAddressDictFromAddressBookRecord:payment.billingAddress];
        
        if (!billingAddressDict) {
            // something's went wrong and we don't have a billing address - fail...
            completion(PKPaymentAuthorizationStatusInvalidBillingPostalAddress);
            return;
        }
        
    } else {
        // we can't complete payment without a billing address!
        // inform the payment view
        completion(PKPaymentAuthorizationStatusInvalidBillingPostalAddress);
        return;
    }
    
    NSDictionary *shippingAddressDict = nil;
    if (payment.shippingAddress) {
        shippingAddressDict = [self createAddressDictFromAddressBookRecord:payment.shippingAddress];
        
        if (!shippingAddressDict) {
            // something's went wrong and we don't have a shipping address - fail...
            completion(PKPaymentAuthorizationStatusInvalidShippingContact);
            return;
        }
        
    } else {
        // we can't complete payment without a shipping address!
        // inform the payment view
        completion(PKPaymentAuthorizationStatusInvalidShippingContact);
        return;
    }
    
    // get the shipping method
    NSString *shippingMethodSlug = payment.shippingMethod.identifier;
    
    // and the billing email
    NSString *billingEmail = [self emailAddressFromAddressBookRecord:payment.shippingAddress];
    if (!billingEmail) {
        // not enough information - fail.
        completion(PKPaymentAuthorizationStatusInvalidShippingContact);
        return;
    }
    
    NSLog(@"billingAddressDict = %@", billingAddressDict);
    NSLog(@"shippingAddressDict = %@", shippingAddressDict);
    NSLog(@"shippingMethodSlug = %@", shippingMethodSlug);
    NSLog(@"billingEmail = %@", billingEmail);
    
    
    [Stripe createTokenWithPayment:payment
                        completion:^(STPToken *token, NSError *error) {
                            // charge your Stripe token as normal
                            NSString *tokenValue = token.tokenId;
                            
                            // we can now pass tokenValue up to Moltin to charge - let's do the moltin checkout.
                            
                            // Firstly, we need to carry out the order with Moltin
                            [self getCustomerIdWithEmail:billingEmail andFirstName:billingAddressDict[@"first_name"] andLastName:billingAddressDict[@"last_name"] withCompletionBlock:^(NSString *customerId) {
                                NSLog(@"%@", customerId);
                                
                                // if customerId is nil, transaction has failed.
                                if (!customerId) {
                                    // transaction failed...
                                    
                                    completion(PKPaymentAuthorizationStatusFailure);
                                    
                                    return;
                                }
                                
                                
                                // it seems we have a customerId, let's continue...
                                NSDictionary *orderParameters = @{
                                                                  @"customer" : customerId,
                                                                  @"shipping" : shippingMethodSlug,
                                                                  @"gateway"  : ApplePayPaymentGateway,
                                                                  @"bill_to"  : billingAddressDict,
                                                                  @"ship_to"  : shippingAddressDict
                                                                  };
                                
                                [[Moltin sharedInstance].cart orderWithParameters:orderParameters
                                                                          success:^(NSDictionary *response)
                                 {
                                     if ([[response valueForKey:@"status"] boolValue]) {
                                         NSString *orderId = [response valueForKeyPath:@"result.id"];
                                         // go ahead and pay...
                                         
                                         // we're paying using the value of the token that the Stripe API has provided us with...
                                         NSDictionary *paymentParameters = @{ @"token": tokenValue };
                                         
                                         [[Moltin sharedInstance].checkout paymentWithMethod:PAYMENT_METHOD
                                                                                       order:orderId
                                                                                  parameters:paymentParameters
                                                                                     success:^(NSDictionary *response)
                                          {
                                              if ([[response valueForKey:@"status"] boolValue]) {
                                                  [[NSNotificationCenter defaultCenter] postNotificationName:kMoltinNotificationRefreshCart object:nil];
                                                  
                                                  NSDictionary *receipt = response;
                                                  NSLog(@"payment success with receipt = %@", receipt);
                                                  // TODO: show receipt properly!
                                                  
                                                  // success!
                                                  completion(PKPaymentAuthorizationStatusSuccess);
                                                  
                                                  
                                              }
                                              else{
                                                  // failed horribly...
                                                  
                                                  NSString *responseMessage = [response valueForKey:@"error"];
                                                  ALERT(@"Payment error", responseMessage);
                                                  NSLog(@"ERROR PAYMENT: %@", response);
                                                  completion(PKPaymentAuthorizationStatusFailure);
                                              }
                                              
                                          } failure:^(NSDictionary *response, NSError *error) {
                                              
                                              NSString *errorMessage = error.localizedDescription;
                                              if (response && ![[response valueForKey:@"status"] boolValue]) {
                                                  NSString *responseMessage = [response valueForKey:@"error"];
                                                  NSLog(@"ERROR: %@", response);
                                                  errorMessage = responseMessage;
                                              }
                                              ALERT(@"Payment error", errorMessage);
                                              
                                              completion(PKPaymentAuthorizationStatusFailure);
                                              
                                          }];
                                         
                                     }
                                     else{
                                         // transaction failed...
                                         completion(PKPaymentAuthorizationStatusFailure);
                                         
                                         NSString *responseMessage = [response valueForKey:@"error"];
                                         NSLog(@"ERROR: %@", response);
                                         ALERT(@"Order error", responseMessage);
                                         
                                         completion(PKPaymentAuthorizationStatusFailure);
                                         
                                     }
                                     
                                 } failure:^(NSDictionary *response, NSError *error) {
                                     // transaction failed...
                                     
                                     NSString *errorMessage = error.localizedDescription;
                                     if (response && ![[response valueForKey:@"status"] boolValue]) {
                                         NSString *responseMessage = [response valueForKey:@"error"];
                                         NSLog(@"ERROR: %@", response);
                                         errorMessage = responseMessage;
                                     }
                                     ALERT(@"Order error", errorMessage);
                                     
                                     completion(PKPaymentAuthorizationStatusFailure);
                                     
                                 }];
                                
                                
                            }];
                            
                            
                        }];
    
    
}

- (void)getCustomerIdWithEmail:(NSString*)email andFirstName:(NSString*)firstName andLastName:(NSString*)lastName withCompletionBlock:(void (^) (NSString *customerId))completion {
    
    [[Moltin sharedInstance].customer findWithParameters:@{ @"email" : email }
                                                 success:^(NSDictionary *response)
     {
         NSArray *result = [response objectForKey:@"result"];
         if (result.count == 0) {
             // create customer
             
             [[Moltin sharedInstance].customer createWithParameters:@{@"first_name" : firstName, @"last_name" : lastName, @"email" : email}
                                                            success:^(NSDictionary *response)
              {
                  if ([[response valueForKey:@"status"] boolValue]) {
                      NSString *customerId = [response valueForKeyPath:@"result.id"];
                      completion(customerId);
                  }
                  else{
                      NSLog(@"ERROR CREATING CUSTOMER: %@", response);
                      NSString *errors = [[response objectForKey:@"errors"] firstObject];
                      ALERT(@"Error creating customer", errors);
                      completion(nil);
                      
                  }
                  
              } failure:^(NSDictionary *response, NSError *error) {
                  NSString *errorMessage = error.localizedDescription;
                  if (response && ![[response valueForKey:@"status"] boolValue]) {
                      NSString *responseMessage = [[response objectForKey:@"errors"] firstObject];
                      NSLog(@"ERROR: %@", response);
                      errorMessage = responseMessage;
                  }
                  ALERT(@"Error creating customer", errorMessage);
                  completion(nil);
                  
              }];
             
             
         }
         else{
             NSString *customerId = [[result firstObject] valueForKey:@"id"];
             completion(customerId);
         }
     } failure:^(NSDictionary *response, NSError *error) {
         NSString *errorMessage = error.localizedDescription;
         if (response && ![[response valueForKey:@"status"] boolValue]) {
             NSString *responseMessage = [[response objectForKey:@"errors"] firstObject];
             NSLog(@"ERROR: %@", response);
             errorMessage = responseMessage;
         }
         ALERT(@"Error", errorMessage);
         completion(nil);
     }];
    
    
}

- (NSDictionary *)createAddressDictFromAddressBookRecord:(ABAddressBookRef)record {
    // extract address from record, as per the Stripe API ( https://github.com/stripe/stripe-ios/blob/master/Stripe/ApplePay/STPAPIClient%2BApplePay.m )
    
    NSMutableDictionary *addressDict = [NSMutableDictionary dictionary];
    
    NSString *firstName = (__bridge_transfer NSString*)ABRecordCopyValue(record, kABPersonFirstNameProperty);
    if (firstName) {
        addressDict[@"first_name"] = firstName;
    }
    
    NSString *lastName = (__bridge_transfer NSString*)ABRecordCopyValue(record, kABPersonLastNameProperty);
    if (lastName) {
        addressDict[@"last_name"] = lastName;
    }
    
    ABMultiValueRef addressValues = ABRecordCopyValue(record, kABPersonAddressProperty);
    
    if (addressValues != NULL) {
        if (ABMultiValueGetCount(addressValues) > 0) {
            CFDictionaryRef dict = ABMultiValueCopyValueAtIndex(addressValues, 0);
            
            NSString *streetAddress = CFDictionaryGetValue(dict, kABPersonAddressStreetKey);
            if (streetAddress) {
                addressDict[@"address_1"] = streetAddress;
            }
            
            NSString *city = CFDictionaryGetValue(dict, kABPersonAddressCityKey);
            if (city) {
                addressDict[@"address_2"] = city;
            }
            
            NSString *state = CFDictionaryGetValue(dict, kABPersonAddressStateKey);
            if (state) {
                if (addressDict[@"address_2"]) {
                    // append state to the existing address_2
                    addressDict[@"address_2"] = [addressDict[@"address_2"] stringByAppendingString:[NSString stringWithFormat:@", %@", state]];
                } else {
                    // make address_2 the state instead...
                    addressDict[@"address_2"] = state;
                }
            }
            
            NSString *postcode = CFDictionaryGetValue(dict, kABPersonAddressZIPKey);
            if (postcode) {
                addressDict[@"postcode"] = postcode;
            }
            
            NSString *country = CFDictionaryGetValue(dict, kABPersonAddressCountryKey);
            if (country) {
                
                NSArray *possibleCountries = [self.countries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", country]];
                
                if (possibleCountries && possibleCountries.count > 0) {
                    NSLog(@"found possible country");
                    NSString *countryCode = [possibleCountries[0] objectForKey:@"code"];
                    addressDict[@"country"] = countryCode;

                } else {
                    addressDict[@"country"] = country;
 
                }
                
            }
            
            CFRelease(dict);
            
        }
        
        CFRelease(addressValues);
        
    } else {
        // we don't actually have an address - return nil...
        return nil;
        
    }
    
    return addressDict;
    
}

- (NSString*)emailAddressFromAddressBookRecord:(ABAddressBookRef)record {
    ABMultiValueRef contactEmails = ABRecordCopyValue(record, kABPersonEmailProperty);
    
    if (!contactEmails) {
        return nil;
    }
    
    CFArrayRef allEmails = ABMultiValueCopyArrayOfAllValues(contactEmails);
    
    if (!allEmails) {
        return nil;
    }
    
    NSArray *emails = (__bridge NSArray *)allEmails;
    
    CFRelease(allEmails);
    CFRelease(contactEmails);
    
    if (emails && emails.count > 0) {
        return [emails firstObject];
    } else {
        return nil;
    }
    
}

- (void)paymentAuthorizationViewControllerDidFinish:(PKPaymentAuthorizationViewController *)controller {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    [controller dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - TableView
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.cartItems.count;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    CartListCell *cell = [tableView dequeueReusableCellWithIdentifier:CartCellIdentifier];
    if (cell == nil) {
        
        cell = [[CartListCell alloc] init];
    }
    
    NSDictionary *cartItem = [self.cartItems objectAtIndex:indexPath.row];
    [cell configureWithCartItemDict:cartItem];
    cell.delegate = self;
    
    return cell;
}

-(void)updateCartWithProductId:(NSString *)productId andQuantity:(NSNumber *)quantity
{
    __weak CartViewController *weakSelf = self;
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    hud.labelText = @"Updating Cart";
    
    // if quantity is zero, the Moltin API automagically knows to remove the item from the cart
    // update to new quantity value...
    [[Moltin sharedInstance].cart updateItemWithId:productId parameters:@{@"quantity" : quantity}
                                           success:^(NSDictionary *response){
                                               [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
                                               [weakSelf loadCart];
                                           }
                                           failure:^(NSDictionary *response, NSError *error) {
                                               [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
                                               NSLog(@"ERROR CART UPDATE: %@", error);
                                               [weakSelf loadCart];
                                           }];
    
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return YES if you want the specified item to be editable.
    return YES;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // remove item at indexPath.row from the cart...
        NSString *productIdString = [[self.cartItems objectAtIndex:indexPath.row] objectForKey:@"id"];
        
        // weakSelf allows us to refer to self safely inside of the completion handler blocks.
        __weak CartViewController *weakSelf = self;
        
        // show some loading UI...
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.labelText = @"Updating Cart";
        
        // now remove it...
        [[Moltin sharedInstance].cart removeItemWithId:productIdString success:^(NSDictionary *response) {
            // hide loading dialog and refresh...
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
            [weakSelf loadCart];
        } failure:^(NSDictionary *response, NSError *error) {
            // log error, hide loading dialog, refresh...
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
            NSLog(@"ERROR CART UPDATE: %@", error);
            [weakSelf loadCart];
        }];
        
    }
}

@end
