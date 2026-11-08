#import <Foundation/Foundation.h>
#import "ASGMatchers.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        for (NSString *s in @[@"跳过", @" Skip ", @"跳过 3s", @"跳过(5秒)", @"SKIP 2", @"5s 跳过", @"跳过广告 3秒",
                             @"3 | 跳过", @"Skip ad (4)", @"跳过(0)", @"Skip in 3", @"３秒後跳過", @">>", @"点击跳过"])
            assert(ASGActionForText(s) == ASGActionSkip);
        for (NSString *s in @[@"关闭", @"关闭|4s", @"关闭 3秒", @"关闭广告×", @"关闭此广告", @"Close ad", @"Dismiss ad x", @"關閉｜４s"])
            assert(ASGActionForText(s) == ASGActionCloseAd);
        for (NSString *s in @[@"登录", @"立即领取", @"继续", @"X", @"", @"广告投放"])
            assert(ASGActionForText(s) == ASGActionNone);
        for (NSString *s in @[@"点击跳过登录", @"跳过教程", @"skip login", @"关闭订单", @"关闭账号", @"关闭广告设置", @"开通VIP关闭广告", @"skipper_profile"])
            assert(ASGUnsafeActionText(s));
        assert(ASGSkipIdentifier(@"sdk_skip_button"));
        assert(ASGSkipIdentifier(@"skipAdButton"));
        assert(ASGAdClass(@"BUSplashAdView"));
        assert(ASGAdClass(@"GADAppOpenAdController"));
        assert(!ASGAdClass(@"LoadingSplashView"));
        assert(!ASGAdClass(nil));
        assert(ASGCountdownSeconds(@"关闭|4s") == 4);
        assert(ASGCountdownSeconds(@"關閉｜４s") == 4);
        assert(ASGCountdownSeconds(@"Skip in 3") == 3);
        assert(ASGCountdownSeconds(@"关闭|0s") == 0);
        assert(ASGCountdownSeconds(@"跳过 100秒") == -1);
        assert(ASGCountdownSeconds(@"跳过 3秒 4秒") == -1);
        assert(ASGCountdownSeconds(@"关闭 4s 关闭|4s") == 4);
        assert(!ASGCountdownText(@"跳过教程3"));
        assert(ASGArrowText(@">>"));
        assert(!ASGArrowText(@"跳过 >>"));
        assert(ASGExplicitAdText(@"关闭广告"));
        assert(!ASGExplicitAdText(@"开通VIP关闭广告"));
        assert([ASGSkipMeaning(@"跳过 3s") isEqual:ASGSkipMeaning(@"跳过 2s")]);
        assert(ASGActionForText(nil) == ASGActionNone);
        for (NSString *s in @[@"广告2s", @"广告 5 秒", @"廣告｜４s", @"ad 3 seconds", @"advertisement(2sec)", @"广告 3 s", @"广告2s 广告2s", @"3s | 广告", @"2秒 广告"]) {
            assert(ASGActionForText(s) == ASGActionAdCountdown);
            assert(ASGCountdownSeconds(s) >= 0);
        }
        assert(ASGActionForText(@"广告25") == ASGActionNone);
        assert(ASGActionForOCRText(@"广告25") == ASGActionAdCountdown);
        assert(ASGCountdownSeconds(@"广告25") == -1); // Never treat OCR s->5 as 25 real seconds.
        assert(ASGActionPriority(ASGActionSkip) == ASGActionPriority(ASGActionCloseAd));
        assert(ASGActionPriority(ASGActionSkip) < ASGActionPriority(ASGActionAdCountdown));
        assert(ASGActionPriority(ASGActionAdCountdown) < ASGActionPriority(ASGActionNone));
        for (NSString *s in @[@"广告预算25", @"广告2026", @"比赛2s", @"倒计时5s", @"广告投放2秒", @"广告费用2s", @"立即领取广告2s"]) {
            assert(ASGActionForText(s) == ASGActionNone);
            assert(ASGActionForOCRText(s) == ASGActionNone);
        }
        // 240 combinations, not individual App rules: labels x decorations x digits.
        for (NSString *label in @[@"跳过", @"skip", @"关闭", @"close"])
            for (NSString *separator in @[@" ", @"|", @"｜"])
                for (unsigned second = 0; second < 20; second++) {
                    NSString *s = [NSString stringWithFormat:@"%@%@%us", label, separator, second];
                    assert(ASGActionForText(s) != ASGActionNone);
                    assert(ASGCountdownSeconds(s) == second);
                }
        puts("PASS matchers: original four-keyword discovery, Unicode/countdown variants, negative authorization evidence, 240 combinations");
    }
    return 0;
}
